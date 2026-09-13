import Foundation
import Observation
import SwiftUI

/// Which appearance the app draws in — independent of the system setting, since the Pencil
/// design ships explicit light/dark values rather than deriving dark from light.
enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` lets SwiftUI fall through to the system setting — `.preferredColorScheme` only
    /// forces an override for `.light`/`.dark`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// How long a history entry survives before `RunLog` purges it automatically.
enum AutoDeleteInterval: String, CaseIterable, Sendable {
    case never
    case oneDay
    case threeDays
    case sevenDays
    case thirtyDays

    var displayName: String {
        switch self {
        case .never: "Never"
        case .oneDay: "After 1 day"
        case .threeDays: "After 3 days"
        case .sevenDays: "After 7 days"
        case .thirtyDays: "After 30 days"
        }
    }

    /// Entries older than this are purged. `nil` means keep everything.
    var maxAge: TimeInterval? {
        switch self {
        case .never: nil
        case .oneDay: 86_400
        case .threeDays: 3 * 86_400
        case .sevenDays: 7 * 86_400
        case .thirtyDays: 30 * 86_400
        }
    }
}

/// Which speech engine transcribes an utterance.
enum SpeechEngineChoice: String, CaseIterable, Sendable {
    case apple
    case parakeet
    /// The only engine that covers Arabic (plus 13 other languages) — Apple's
    /// `SpeechTranscriber` and both Parakeet checkpoints don't.
    case cohere

    var displayName: String {
        switch self {
        case .apple: "Apple (streaming)"
        case .parakeet: "Parakeet (batch)"
        case .cohere: "Cohere Transcribe (batch)"
        }
    }

    /// Apple shows text while you talk; the batch engines only resolve on release.
    var showsLiveText: Bool { self == .apple }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    var pushToTalkKey: PushToTalkKey {
        didSet {
            guard let data = try? JSONEncoder().encode(pushToTalkKey) else { return }
            defaults.set(data, forKey: Keys.pushToTalkKey)
        }
    }

    /// On: hold the transcribe key to record, release to stop (the default). Off: press
    /// once to start, press again to stop — the key's release is ignored either way, so
    /// switching this doesn't need a different key.
    var pushToTalkEnabled: Bool {
        didSet { defaults.set(pushToTalkEnabled, forKey: Keys.pushToTalkEnabled) }
    }

    var engine: SpeechEngineChoice {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    /// Run every engine on each recording and show them side by side, instead of
    /// transcribing with one. Nothing is typed into the focused app in this mode.
    var compareMode: Bool {
        didSet { defaults.set(compareMode, forKey: Keys.compareMode) }
    }

    /// Run the cleanup pass before injecting. Off = raw engine output.
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }

    /// Use the on-device LLM for cleanup instead of the deterministic rule pass.
    var smartCleanup: Bool {
        didSet { defaults.set(smartCleanup, forKey: Keys.smartCleanup) }
    }

    /// Play a short tick when capture starts and stops.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    /// Filters silence out of the capture in real time. Streaming-capable engines (Apple)
    /// keep a longer tail after speech drops off, since cutting audio too eagerly costs
    /// them recognition context; batch engines can afford a shorter one. Off records raw,
    /// unfiltered audio.
    var vadEnabled: Bool {
        didSet { defaults.set(vadEnabled, forKey: Keys.vadEnabled) }
    }

    /// Strips hesitation words (um, uh, …) during cleanup. Independent of `cleanupEnabled`
    /// so a user who wants punctuation/spacing fixes but not filler removal can have both —
    /// though with cleanup off entirely, this has nothing to act on.
    var removeFillerWords: Bool {
        didSet { defaults.set(removeFillerWords, forKey: Keys.removeFillerWords) }
    }

    /// A BCP-47 identifier ("en-US", "es-ES", …), or "auto" for the system's current
    /// locale. Only `AppleSpeechEngine` honors this — Parakeet is English-only.
    var speechLanguage: String {
        didSet { defaults.set(speechLanguage, forKey: Keys.speechLanguage) }
    }

    /// Runs the transcript through on-device translation before injection. Only takes
    /// effect with a specific `speechLanguage` selected — translation needs a known source
    /// language, so it's a no-op while `speechLanguage` is "auto".
    var translateToEnglish: Bool {
        didSet { defaults.set(translateToEnglish, forKey: Keys.translateToEnglish) }
    }

    /// CoreAudio device UID of the chosen input, or nil for whatever macOS considers the
    /// default input device.
    var microphoneDeviceID: String? {
        didSet { defaults.set(microphoneDeviceID, forKey: Keys.microphoneDeviceID) }
    }

    /// Mutes the default output device for the duration of a recording, so the mic doesn't
    /// pick up whatever's playing. Restored the moment the recording ends, regardless of
    /// whether this is still on by then.
    var muteWhileRecording: Bool {
        didSet { defaults.set(muteWhileRecording, forKey: Keys.muteWhileRecording) }
    }

    /// Overrides the system appearance for Shush's own windows. `DS.Color` resolves per the
    /// window's actual drawn appearance, so this is enough to make every token switch —
    /// nothing else needs to know about it.
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Oldest entries beyond this count are trimmed from `RunLog` whenever a new one is
    /// recorded.
    var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) }
    }

    /// Entries older than this are purged from `RunLog` on the same schedule.
    var autoDeleteInterval: AutoDeleteInterval {
        didSet { defaults.set(autoDeleteInterval.rawValue, forKey: Keys.autoDeleteInterval) }
    }

    /// Show release notes after an update. No changelog UI exists yet — this just holds the
    /// preference for when one does.
    var showWhatsNew: Bool {
        didSet { defaults.set(showWhatsNew, forKey: Keys.showWhatsNew) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let pushToTalkKey = "pushToTalkKey"
        static let pushToTalkEnabled = "pushToTalkEnabled"
        static let cleanupEnabled = "cleanupEnabled"
        static let soundEnabled = "soundEnabled"
        static let vadEnabled = "vadEnabled"
        static let removeFillerWords = "removeFillerWords"
        static let engine = "engine"
        static let smartCleanup = "smartCleanup"
        static let compareMode = "compareMode"
        static let speechLanguage = "speechLanguage"
        static let translateToEnglish = "translateToEnglish"
        static let microphoneDeviceID = "microphoneDeviceID"
        static let muteWhileRecording = "muteWhileRecording"
        static let appearance = "appearance"
        static let historyLimit = "historyLimit"
        static let autoDeleteInterval = "autoDeleteInterval"
        static let showWhatsNew = "showWhatsNew"
    }

    private init() {
        if let data = defaults.data(forKey: Keys.pushToTalkKey),
           let decoded = try? JSONDecoder().decode(PushToTalkKey.self, from: data) {
            pushToTalkKey = decoded
        } else {
            pushToTalkKey = .default
        }
        pushToTalkEnabled = defaults.object(forKey: Keys.pushToTalkEnabled) as? Bool ?? true
        // Apple by default: no download, no dependency, live text while speaking.
        engine = SpeechEngineChoice(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .apple
        cleanupEnabled = defaults.object(forKey: Keys.cleanupEnabled) as? Bool ?? true
        smartCleanup = defaults.object(forKey: Keys.smartCleanup) as? Bool ?? false
        compareMode = defaults.object(forKey: Keys.compareMode) as? Bool ?? false
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        vadEnabled = defaults.object(forKey: Keys.vadEnabled) as? Bool ?? true
        removeFillerWords = defaults.object(forKey: Keys.removeFillerWords) as? Bool ?? true
        speechLanguage = defaults.string(forKey: Keys.speechLanguage) ?? "auto"
        translateToEnglish = defaults.object(forKey: Keys.translateToEnglish) as? Bool ?? false
        microphoneDeviceID = defaults.string(forKey: Keys.microphoneDeviceID)
        muteWhileRecording = defaults.object(forKey: Keys.muteWhileRecording) as? Bool ?? false
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        let storedLimit = defaults.object(forKey: Keys.historyLimit) as? Int
        historyLimit = storedLimit ?? 10
        autoDeleteInterval = AutoDeleteInterval(
            rawValue: defaults.string(forKey: Keys.autoDeleteInterval) ?? ""
        ) ?? .threeDays
        showWhatsNew = defaults.object(forKey: Keys.showWhatsNew) as? Bool ?? true
    }
}
