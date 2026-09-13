import ShushDictionary
import AVFoundation
import AppKit
import FluidAudio
import Foundation
import Observation

/// Builds the engine named by the current setting.
///
/// Deliberately at file scope rather than a static on `DictationController`: the class is
/// `@MainActor`, which would make a static method main-actor-isolated and therefore
/// ineligible to be `@Sendable`. Reading the setting per-utterance is what lets the menu's
/// engine picker take effect on the very next hold instead of needing a restart.
@Sendable
func engineForCurrentSetting() -> any TranscriptionEngine {
    // Always invoked from `beginDictation`, which runs on the main actor.
    MainActor.assumeIsolated {
        switch Settings.shared.engine {
        case .apple:
            let language = Settings.shared.speechLanguage
            return AppleSpeechEngine(locale: language == "auto" ? Locale.current : Locale(identifier: language))
        case .parakeet:
            return ParakeetEngine()
        case .cohere:
            let language = Settings.shared.speechLanguage
            let code = String(language.prefix(2)).lowercased()
            return CohereEngine(language: CohereAsrConfig.Language(rawValue: code) ?? .english)
        }
    }
}

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case finishing
        case error(String)

        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            case .idle, .error: false
            }
        }
    }

    private(set) var state: State = .idle
    /// Live transcript, updated as the engine revises it. Drives the HUD.
    private(set) var transcript = ""
    /// Smoothed 0…1 mic level for the waveform.
    private(set) var level: Float = 0

    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    /// Escape, watched only while a recording is active — a passive observer, so it never
    /// swallows Escape presses that belong to whatever app has focus.
    private var cancelMonitor: Any?
    private let makeEngine: @Sendable () -> any TranscriptionEngine

    /// Injected only by tests; production reads the setting per-utterance below.
    private let formatter: (any TextFormatter)?

    /// Chosen per-utterance so the menu toggle applies to the very next hold.
    private var activeFormatter: any TextFormatter {
        if let formatter { return formatter }
        let removeFillerWords = Settings.shared.removeFillerWords
        return Settings.shared.smartCleanup
            ? FoundationModelFormatter(removeFillerWords: removeFillerWords)
            : RuleBasedFormatter(removeFillerWords: removeFillerWords)
    }

    private var engine: (any TranscriptionEngine)?
    private var consumeTask: Task<Void, Never>?
    /// Returns the ordered recording when compare mode is on, empty otherwise.
    private var feedTask: Task<[AudioChunk], Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    /// Timestamps for the dashboard: when the key went down, and when it came up.
    private var holdStarted: Date?
    private var releasedAt: Date?
    private var engineName = ""

    /// Compare mode only: the recording, kept so every engine sees identical audio.
    private var recorded: [AudioChunk] = []
    private var isComparing = false

    /// Whether this hold actually muted the output — only true if `muteWhileRecording` was
    /// on *and* the mute call succeeded, so `endDictation`/`cancelDictation` know whether
    /// there's anything to restore.
    private var mutedForRecording = false

    init(
        formatter: (any TextFormatter)? = nil,
        makeEngine: @escaping @Sendable () -> any TranscriptionEngine = engineForCurrentSetting
    ) {
        self.formatter = formatter
        self.makeEngine = makeEngine
    }

    // MARK: - Lifecycle

    /// - Returns: `false` if the hotkey tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        hotkey.key = Settings.shared.pushToTalkKey
        // In toggle mode the key's release is ignored entirely — press starts or stops
        // depending on current state, so a stray release (e.g. the tap losing the key
        // briefly) can't stop a recording the user meant to keep going.
        hotkey.onPress = { [weak self] in
            guard let self else { return }
            if Settings.shared.pushToTalkEnabled {
                self.beginDictation()
            } else if self.state.isActive {
                self.endDictation()
            } else {
                self.beginDictation()
            }
        }
        hotkey.onRelease = { [weak self] in
            guard let self, Settings.shared.pushToTalkEnabled else { return }
            self.endDictation()
        }
        installCancelMonitor()
        return hotkey.start()
    }

    func deactivate() {
        hotkey.stop()
        removeCancelMonitor()
        cancelDictation()
    }

    /// Cancels the in-progress recording — discards the audio, injects nothing. Wired to
    /// Escape while a recording is active.
    func cancelCurrentRecording() {
        guard state.isActive else { return }
        cancelDictation()
    }

    private func installCancelMonitor() {
        guard cancelMonitor == nil else { return }
        cancelMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 /* Escape */ else { return }
            Task { @MainActor in self?.cancelCurrentRecording() }
        }
    }

    private func removeCancelMonitor() {
        if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) }
        cancelMonitor = nil
    }

    /// Re-arms the tap after the user picks a different push-to-talk key.
    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.stop()
        return activate()
    }

    // MARK: - Button-driven recording

    /// Starts a recording from a Record button rather than the hotkey.
    ///
    /// Wispr Flow's hotkey is held down for the duration **only in compare mode**. Reaching
    /// into another app is a comparison affordance; during ordinary dictation it would mean
    /// every recording silently shipped your audio to a third party's servers.
    func startButtonRecording() {
        guard case .idle = state else { return }
        if Settings.shared.compareMode { WisprTrigger.press() }
        beginDictation()
    }

    /// Releases Wispr's hotkey first, so its upload starts while our own engines are still
    /// finishing — otherwise every run would wait the full round trip end to end.
    func stopButtonRecording() {
        WisprTrigger.release()
        endDictation()
    }

    // MARK: - Dictation

    private func beginDictation() {
        guard case .idle = state else { return }
        state = .starting
        transcript = ""
        holdStarted = Date()
        isComparing = Settings.shared.compareMode
        recorded.removeAll(keepingCapacity: true)
        engineName = isComparing ? "Comparing…" : Settings.shared.engine.displayName

        if Settings.shared.muteWhileRecording {
            mutedForRecording = SystemAudio.setOutputMuted(true)
        }

        Task { @MainActor in
            do {
                guard await Permissions.requestMicrophone() else {
                    fail("Microphone access is off. Enable it in System Settings ▸ Privacy & Security ▸ Microphone.")
                    return
                }

                let engine = makeEngine()
                self.engine = engine

                let chunks = try await engine.start()

                // Compare mode captures in *Apple's* format, not a format of our choosing.
                //
                // SpeechAnalyzer enforces `Audio sample data must be 16-bit signed integers`
                // as a hard precondition — feeding it float32 doesn't fail gracefully, it
                // kills the process. Parakeet is the flexible one (its `feed` converts
                // int16/int32/float32), so the strict engine picks the format and the
                // tolerant engine adapts. Both still replay the identical buffers.
                let formatOwner: any TranscriptionEngine = isComparing ? AppleSpeechEngine() : engine
                guard let format = await formatOwner.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }

                // Audio must reach the engine in capture order. A stream plus a single
                // draining task guarantees that; spawning a Task per buffer would not.
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                self.audioContinuation = audioContinuation

                // The recording is accumulated *inside* the ordered drain, not by spawning
                // a task per buffer. Unstructured tasks have no ordering guarantee, so
                // collecting them separately could assemble the replay audio out of order
                // and silently produce word-salad from the comparison.
                let comparing = isComparing
                self.feedTask = Task.detached(priority: .userInitiated) {
                    var recording: [AudioChunk] = []
                    for await chunk in audioStream {
                        if comparing { recording.append(chunk) }
                        await engine.feed(chunk)
                    }
                    return recording
                }

                let microphoneDeviceID = Settings.shared.microphoneDeviceID
                    .flatMap { MicrophoneDevices.resolve(uid: $0)?.audioDeviceID }

                try capture.start(
                    outputFormat: format,
                    microphoneDeviceID: microphoneDeviceID,
                    vadEnabled: Settings.shared.vadEnabled,
                    vadTailSeconds: Settings.shared.engine.showsLiveText ? 0.8 : 0.35,
                    onBuffer: { chunk in
                        audioContinuation.yield(chunk)
                    },
                    onLevel: { [weak self] level in
                        Task { @MainActor in self?.updateLevel(level) }
                    }
                )

                // Bail out if the user already let go while we were spinning up.
                guard case .starting = self.state else {
                    await self.teardown()
                    return
                }

                self.state = .listening
                if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            self.transcript = chunk.text
                        }
                    } catch {
                        self.fail(error.localizedDescription)
                    }
                }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func endDictation() {
        // `.finishing` is "active", so without this a second press during processing would
        // run the whole tail again — re-reading `transcript` before the first pass cleared
        // it and pasting the same utterance twice. The window is wide: Parakeet transcribes
        // inside `finish()`, and smart cleanup adds up to 4s on top.
        guard state.isActive, state != .finishing else { return }
        state = .finishing
        capture.stop()
        level = 0
        releasedAt = Date()
        unmuteIfNeeded()

        Task { @MainActor in
            // Drain every captured buffer into the engine before asking it to finalize,
            // or the tail of the utterance gets dropped.
            audioContinuation?.finish()
            audioContinuation = nil

            // A wedged engine call (native model code stuck, `finalizeAndFinishThroughEndOfInput`
            // never returning) used to leave `state` parked at `.finishing` forever — the HUD
            // stuck on "Transcribing…" and every further hold a no-op, since `endDictation`
            // guards on `state != .finishing`. Race the finalize sequence against a timeout so
            // the app always recovers to `.idle` even if the stuck call itself never unblocks;
            // the abandoned task is left to finish (or not) on its own rather than blocking UI.
            let outcome = await withTaskGroup(of: [AudioChunk]?.self) { group in
                // `TaskGroup.addTask { @MainActor in ... self ... }` directly trips a Swift
                // region-isolation-checker bug ("pattern the checker does not understand").
                // Routing through a plain `Task { @MainActor in }.value` from a non-isolated
                // addTask closure sidesteps it.
                group.addTask { await Task { @MainActor in await self.drainFeedFinishAndConsume() }.value }
                group.addTask {
                    try? await Task.sleep(for: .seconds(30))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            feedTask = nil
            consumeTask = nil
            engine = nil

            guard let recording = outcome else {
                Log.speech.error("dictation finalize timed out after 30s — resetting to idle")
                fail("Transcription took too long and was cancelled.")
                return
            }
            recorded = recording

            if isComparing {
                await runComparison()
                return
            }

            let raw = transcript
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .idle
                transcript = ""
                return
            }

            let cleaned = Settings.shared.cleanupEnabled
                ? await activeFormatter.format(raw)
                : raw

            // The dictionary runs last, and runs regardless of the cleanup setting. Biasing
            // only raises the odds of the right word; this is the pass that guarantees it,
            // so it must not be something the user can accidentally switch off.
            var (output, corrections) = DictionaryStore.shared.corrector.apply(to: cleaned)
            if !corrections.isEmpty {
                Log.speech.info("dictionary · \(corrections.count, privacy: .public) correction(s) applied")
            }

            if Settings.shared.translateToEnglish {
                output = await Translator.translateToEnglish(output, sourceIdentifier: Settings.shared.speechLanguage)
            }

            // Captured right before injection, not at hold-start: the HUD is a
            // non-activating panel, so whatever app is frontmost *now* is the one that's
            // about to receive the text — the one the dashboard should credit.
            let target = NSWorkspace.shared.frontmostApplication
            recordRun(text: output, corrections: corrections, appName: target?.localizedName, appBundleID: target?.bundleIdentifier)
            TextInjector.insert(output)
            if Settings.shared.learnFromCorrectionsEnabled && Permissions.hasAccessibility {
                CorrectionWatcher.shared.observe(injected: output, target: target)
            }
            if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }

            state = .idle
            transcript = ""
        }
    }

    private func cancelDictation() {
        capture.stop()
        unmuteIfNeeded()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil

        let engine = self.engine
        self.engine = nil
        Task { await engine?.finish() }

        state = .idle
        transcript = ""
        level = 0
    }

    private func teardown() async {
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil

        // Same wedged-engine risk as `endDictation`'s finalize race — bound the wait so an
        // early release during startup can't strand `state` at `.finishing` either.
        let finished: Bool? = await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await Task { @MainActor in await self.drainFeedAndFinish() }.value }
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if finished == nil {
            Log.speech.error("dictation teardown timed out after 30s — resetting to idle")
        }

        feedTask = nil
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .idle
    }

    /// The `.finishing`-tail work shared by `endDictation` and `teardown`, factored out so
    /// each can race it against a timeout — a bare `TaskGroup.addTask { @MainActor in ... }`
    /// closure that both awaits actor calls *and* mutates `self` in the same body trips a
    /// Swift region-isolation-checker bug ("pattern the checker does not understand"), so the
    /// work has to live in its own method and the child task just calls it.
    private func drainFeedFinishAndConsume() async -> [AudioChunk] {
        let recording = await feedTask?.value ?? []
        await engine?.finish()
        await consumeTask?.value
        return recording
    }

    private func drainFeedAndFinish() async -> Bool {
        _ = await feedTask?.value
        await engine?.finish()
        return true
    }

    // MARK: - Helpers

    private func unmuteIfNeeded() {
        guard mutedForRecording else { return }
        SystemAudio.setOutputMuted(false)
        mutedForRecording = false
    }

    private func retainForComparison(_ chunk: AudioChunk) {
        guard isComparing else { return }
        recorded.append(chunk)
    }

    /// Replays the recording through every engine and files the results as one group.
    ///
    /// Nothing is injected in this mode — the point is to read the outputs side by side,
    /// and typing one of them into whatever had focus would be a surprise.
    private func runComparison() async {
        let chunks = recorded
        recorded.removeAll(keepingCapacity: false)

        guard !chunks.isEmpty, let holdStarted, let releasedAt else {
            state = .idle
            transcript = ""
            return
        }

        transcript = "Running both engines…"

        let group = UUID().uuidString
        let held = releasedAt.timeIntervalSince(holdStarted)

        // Filed one at a time as each engine finishes, so the window fills in progressively
        // rather than snapping both rows into place at the end.
        let results = await EngineComparison.run(chunks: chunks) { result in
            RunLog.record(
                DictationRun(
                    date: releasedAt,
                    engine: result.engine,
                    audioSeconds: held,
                    processSeconds: result.seconds,
                    text: result.text,
                    group: group
                )
            )
        }

        for result in results {
            Log.speech.info("""
                compare · \(result.engine, privacy: .public): \
                \(result.seconds, format: .fixed(precision: 2))s — \
                \(result.text, privacy: .public)
                """)
        }

        // Wispr Flow, if its hotkey was held for this same utterance. It transcribes in the
        // cloud, so its row lands after both local engines have already finished — the wait
        // happens here rather than blocking the rows above from appearing.
        if WisprReader.isInstalled {
            transcript = "Waiting for Wispr Flow…"
            if let wispr = await WisprReader.result(after: holdStarted, timeout: 8) {
                RunLog.record(
                    DictationRun(
                        date: releasedAt,
                        engine: wispr.engine,
                        audioSeconds: held,
                        processSeconds: wispr.seconds,
                        text: wispr.text,
                        group: group
                    )
                )
                Log.speech.info("""
                    compare · \(wispr.engine, privacy: .public): \
                    \(wispr.seconds, format: .fixed(precision: 2))s — \
                    \(wispr.text, privacy: .public)
                    """)
            } else {
                Log.speech.info("compare · Wispr Flow: no result (hotkey not held, or timed out)")
            }
        }

        self.holdStarted = nil
        self.releasedAt = nil
        isComparing = false
        state = .idle
        transcript = ""

        if Settings.shared.soundEnabled { NSSound(named: "Glass")?.play() }
    }

    /// Files the finished utterance for the dashboard.
    ///
    /// `processSeconds` is measured from key release, not from capture start — that's the
    /// wait the user actually experiences, and it's the only number on which a streaming
    /// engine and a batch engine can be compared honestly.
    private func recordRun(
        text: String,
        corrections: [AppliedCorrection] = [],
        appName: String? = nil,
        appBundleID: String? = nil
    ) {
        guard let holdStarted, let releasedAt else { return }
        RunLog.record(
            DictationRun(
                date: releasedAt,
                engine: engineName,
                audioSeconds: releasedAt.timeIntervalSince(holdStarted),
                processSeconds: Date().timeIntervalSince(releasedAt),
                text: text,
                corrections: corrections.isEmpty ? nil : corrections,
                appName: appName,
                appBundleID: appBundleID
            )
        )
        self.holdStarted = nil
        self.releasedAt = nil
    }

    /// Light smoothing so the waveform glides instead of strobing at buffer rate.
    private func updateLevel(_ new: Float) {
        level += (new - level) * 0.35
    }

    private func fail(_ message: String) {
        Log.app.error("\(message)")
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .error(message)
        level = 0

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = state { state = .idle }
        }
    }
}
