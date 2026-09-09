import AVFoundation
import FluidAudio
import Foundation

/// Cohere Transcribe, via FluidAudio — the only one of Shush's three engines that covers
/// Arabic (also fr/de/es/it/pt/nl/pl/el/ja/zh/vi/ko — see `CohereAsrConfig.Language`).
/// Apple's `SpeechTranscriber` and both Parakeet checkpoints don't: v2 is English-only and
/// v3's "multilingual" is 25 European languages + Japanese, confirmed by querying
/// `SpeechTranscriber.supportedLocales` and reading FluidAudio's own model docs — neither
/// includes Arabic.
///
/// Batch, like Parakeet: audio accumulates while the key is held, transcribed on release.
/// `transcribeLong` handles anything over the encoder's native 35s window via FluidAudio's
/// own sliding-window chunking, so there's no length cap to enforce here.
actor CohereEngine: TranscriptionEngine {
    private var samples: [Float] = []
    private var continuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?
    private let language: CohereAsrConfig.Language
    private let converter = AudioConverter()

    init(language: CohereAsrConfig.Language) {
        self.language = language
    }

    func preferredInputFormat() async -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        samples.removeAll(keepingCapacity: true)
        let (stream, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        self.continuation = continuation

        // Same reasoning as Parakeet: force the (possibly slow, first-run) load here
        // rather than on release, so the wait lands before speaking, not after.
        _ = try await CohereModels.shared.loaded()

        return stream
    }

    func feed(_ chunk: AudioChunk) async {
        let buffer = chunk.buffer
        guard buffer.frameLength > 0 else { return }
        do {
            samples.append(contentsOf: try converter.resampleBuffer(buffer))
        } catch {
            Log.speech.error("Cohere: audio conversion failed — \(error.localizedDescription)")
        }
    }

    func finish() async {
        defer {
            continuation?.finish()
            continuation = nil
            samples.removeAll(keepingCapacity: true)
        }

        guard samples.count >= 1_600 else {
            Log.speech.info("Cohere: skipped — only \(self.samples.count) samples captured")
            return
        }

        do {
            let models = try await CohereModels.shared.loaded()
            let result = try await CohereModels.pipeline.transcribeLong(
                audio: samples, models: models, language: language
            )
            let audioSeconds = Double(samples.count) / 16_000

            Log.speech.info("""
                Cohere: \(audioSeconds, format: .fixed(precision: 1))s audio in \
                \(result.totalSeconds, format: .fixed(precision: 2))s (\(audioSeconds / max(result.totalSeconds, 0.0001), format: .fixed(precision: 0))× realtime)
                """)

            continuation?.yield(
                TranscriptionChunk(text: result.text.trimmingCharacters(in: .whitespacesAndNewlines), isFinal: true)
            )
        } catch {
            Log.speech.error("Cohere failed: \(error.localizedDescription)")
            continuation?.finish(throwing: error)
            continuation = nil
        }
    }
}

/// Process-wide model cache, same shape as `ParakeetModels` — loading is expensive
/// (download once, then a few seconds from disk per process) and the models are immutable
/// once loaded.
actor CohereModels {
    static let shared = CohereModels()
    /// Stateless and cheap to construct; the loaded `MLModel`s are what's expensive, and
    /// those live in `LoadedModels` below.
    static let pipeline = CoherePipeline()

    private static var targetDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("FluidAudio/Models/cohere-transcribe/q8")
    }

    /// Checked without loading — the menu needs this synchronously while drawing.
    nonisolated static var isDownloaded: Bool {
        let dir = targetDirectory
        let needed = [
            ModelNames.CohereTranscribe.encoderCompiledFile,
            ModelNames.CohereTranscribe.decoderCacheExternalV2CompiledFile,
            "vocab.json",
        ]
        return needed.allSatisfy { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    private var loadedModels: CoherePipeline.LoadedModels?
    private var loadTask: Task<CoherePipeline.LoadedModels, Error>?

    var isLoaded: Bool { loadedModels != nil }

    func loaded() async throws -> CoherePipeline.LoadedModels {
        if let loadedModels { return loadedModels }
        if let loadTask { return try await loadTask.value }

        let task = Task<CoherePipeline.LoadedModels, Error> {
            let stage = Self.isDownloaded ? "loading models from disk" : "downloading models (one time)"
            Log.speech.info("Cohere: \(stage, privacy: .public)")
            let started = Date()

            let target = Self.targetDirectory
            if !Self.isDownloaded {
                let modelsBase = target.deletingLastPathComponent().deletingLastPathComponent()
                try await ModelHub.download(.cohereTranscribeCoreml, to: modelsBase)
            }

            let models = try await CoherePipeline.loadModels(
                encoderDir: target, decoderDir: target, vocabDir: target
            )
            Log.speech.info("Cohere: ready in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            return models
        }
        loadTask = task

        do {
            let models = try await task.value
            loadedModels = models
            return models
        } catch {
            loadTask = nil
            throw error
        }
    }
}
