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
            markDirtyForSync()
        }
    }

    /// On: hold the transcribe key to record, release to stop (the default). Off: press
    /// once to start, press again to stop — the key's release is ignored either way, so
    /// switching this doesn't need a different key.
    var pushToTalkEnabled: Bool {
        didSet { defaults.set(pushToTalkEnabled, forKey: Keys.pushToTalkEnabled); markDirtyForSync() }
    }

    var engine: SpeechEngineChoice {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine); markDirtyForSync() }
    }

    /// Run the cleanup pass before injecting. Off = raw engine output.
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled); markDirtyForSync() }
    }

    /// Use the on-device LLM for cleanup instead of the deterministic rule pass.
    var smartCleanup: Bool {
        didSet { defaults.set(smartCleanup, forKey: Keys.smartCleanup); markDirtyForSync() }
    }

    /// Play a short tick when capture starts and stops.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled); markDirtyForSync() }
    }

    /// Filters silence out of the capture in real time. Streaming-capable engines (Apple)
    /// keep a longer tail after speech drops off, since cutting audio too eagerly costs
    /// them recognition context; batch engines can afford a shorter one. Off records raw,
    /// unfiltered audio.
    var vadEnabled: Bool {
        didSet { defaults.set(vadEnabled, forKey: Keys.vadEnabled); markDirtyForSync() }
    }

    /// Strips hesitation words (um, uh, …) during cleanup. Independent of `cleanupEnabled`
    /// so a user who wants punctuation/spacing fixes but not filler removal can have both —
    /// though with cleanup off entirely, this has nothing to act on.
    var removeFillerWords: Bool {
        didSet { defaults.set(removeFillerWords, forKey: Keys.removeFillerWords); markDirtyForSync() }
    }

    /// Watches the field a dictation was just typed into for a short window afterward; if
    /// the edit looks like a targeted word/phrase fix, offers to save it as a dictionary
    /// correction. Off by default — unlike most toggles here, this reads live text out of
    /// whatever app you're using right after Shush's own UI loses relevance, so it's opt-in.
    var learnFromCorrectionsEnabled: Bool {
        didSet { defaults.set(learnFromCorrectionsEnabled, forKey: Keys.learnFromCorrectionsEnabled); markDirtyForSync() }
    }

    /// A BCP-47 identifier ("en-US", "es-ES", …), or "auto" for the system's current
    /// locale. Only `AppleSpeechEngine` honors this — Parakeet is English-only.
    var speechLanguage: String {
        didSet { defaults.set(speechLanguage, forKey: Keys.speechLanguage); markDirtyForSync() }
    }

    /// Runs the transcript through on-device translation before injection. Only takes
    /// effect with a specific `speechLanguage` selected — translation needs a known source
    /// language, so it's a no-op while `speechLanguage` is "auto".
    var translateToEnglish: Bool {
        didSet { defaults.set(translateToEnglish, forKey: Keys.translateToEnglish); markDirtyForSync() }
    }

    /// CoreAudio device UID of the chosen input, or nil for whatever macOS considers the
    /// default input device. Machine-local — deliberately excluded from sync, since another
    /// Mac's device UID is meaningless here.
    var microphoneDeviceID: String? {
        didSet { defaults.set(microphoneDeviceID, forKey: Keys.microphoneDeviceID) }
    }

    /// Mutes the default output device for the duration of a recording, so the mic doesn't
    /// pick up whatever's playing. Restored the moment the recording ends, regardless of
    /// whether this is still on by then.
    var muteWhileRecording: Bool {
        didSet { defaults.set(muteWhileRecording, forKey: Keys.muteWhileRecording); markDirtyForSync() }
    }

    /// Overrides the system appearance for Shush's own windows. `DS.Color` resolves per the
    /// window's actual drawn appearance, so this is enough to make every token switch —
    /// nothing else needs to know about it.
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance); markDirtyForSync() }
    }

    /// Oldest entries beyond this count are trimmed from `RunLog` whenever a new one is
    /// recorded.
    var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit); markDirtyForSync() }
    }

    /// Entries older than this are purged from `RunLog` on the same schedule.
    var autoDeleteInterval: AutoDeleteInterval {
        didSet { defaults.set(autoDeleteInterval.rawValue, forKey: Keys.autoDeleteInterval); markDirtyForSync() }
    }

    /// Show release notes after an update. No changelog UI exists yet — this just holds the
    /// preference for when one does.
    var showWhatsNew: Bool {
        didSet { defaults.set(showWhatsNew, forKey: Keys.showWhatsNew); markDirtyForSync() }
    }

    /// The signed-in Google account's email, or nil when not connected. Display-only — the
    /// tokens that actually authorize sync live in the Keychain (`GoogleAuthService`), not here.
    var googleAccountEmail: String? {
        didSet { defaults.set(googleAccountEmail, forKey: Keys.googleAccountEmail) }
    }

    /// Master switch for Drive sync, independent of sign-in — a signed-in user can pause
    /// syncing without disconnecting the account.
    var syncEnabled: Bool {
        didSet { defaults.set(syncEnabled, forKey: Keys.syncEnabled) }
    }

    /// When the last successful sync completed, for the Account section's subtitle.
    var lastSyncDate: Date? {
        didSet { defaults.set(lastSyncDate, forKey: Keys.lastSyncDate) }
    }

    /// The most recent sync failure's message, cleared on the next success — surfaced in the
    /// Account section so a stale token or network drop doesn't fail silently.
    var lastSyncError: String? {
        didSet { defaults.set(lastSyncError, forKey: Keys.lastSyncError) }
    }

    /// Bumped whenever a syncable setting changes, so `SyncEngine` can last-write-wins against
    /// the Drive copy with one shared timestamp rather than one per field. Not itself synced.
    var settingsLastModified: Date {
        didSet { defaults.set(settingsLastModified, forKey: Keys.settingsLastModified) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let pushToTalkKey = "pushToTalkKey"
        static let pushToTalkEnabled = "pushToTalkEnabled"
        static let cleanupEnabled = "cleanupEnabled"
        static let soundEnabled = "soundEnabled"
        static let vadEnabled = "vadEnabled"
        static let removeFillerWords = "removeFillerWords"
        static let learnFromCorrectionsEnabled = "learnFromCorrectionsEnabled"
        static let engine = "engine"
        static let smartCleanup = "smartCleanup"
        static let speechLanguage = "speechLanguage"
        static let translateToEnglish = "translateToEnglish"
        static let microphoneDeviceID = "microphoneDeviceID"
        static let muteWhileRecording = "muteWhileRecording"
        static let appearance = "appearance"
        static let historyLimit = "historyLimit"
        static let autoDeleteInterval = "autoDeleteInterval"
        static let showWhatsNew = "showWhatsNew"
        static let googleAccountEmail = "googleAccountEmail"
        static let syncEnabled = "syncEnabled"
        static let lastSyncDate = "lastSyncDate"
        static let lastSyncError = "lastSyncError"
        static let settingsLastModified = "settingsLastModified"
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
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        vadEnabled = defaults.object(forKey: Keys.vadEnabled) as? Bool ?? true
        removeFillerWords = defaults.object(forKey: Keys.removeFillerWords) as? Bool ?? true
        learnFromCorrectionsEnabled = defaults.object(forKey: Keys.learnFromCorrectionsEnabled) as? Bool ?? false
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
        googleAccountEmail = defaults.string(forKey: Keys.googleAccountEmail)
        syncEnabled = defaults.object(forKey: Keys.syncEnabled) as? Bool ?? false
        lastSyncDate = defaults.object(forKey: Keys.lastSyncDate) as? Date
        lastSyncError = defaults.string(forKey: Keys.lastSyncError)
        settingsLastModified = defaults.object(forKey: Keys.settingsLastModified) as? Date ?? .distantPast
    }

    /// Called from every syncable property's `didSet`. Skipped while `SyncEngine` is applying a
    /// pulled remote value, so applying a pull doesn't look like a local edit and bounce right
    /// back to Drive.
    private func markDirtyForSync() {
        guard !SyncEngine.shared.isApplyingRemote else { return }
        settingsLastModified = .now
        SyncEngine.shared.scheduleSettingsPush()
    }

    /// Builds the account-level snapshot `SyncEngine` uploads — excludes machine-local settings
    /// like `microphoneDeviceID`.
    func syncSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            pushToTalkKeyData: try? JSONEncoder().encode(pushToTalkKey),
            pushToTalkEnabled: pushToTalkEnabled,
            engine: engine.rawValue,
            cleanupEnabled: cleanupEnabled,
            smartCleanup: smartCleanup,
            soundEnabled: soundEnabled,
            vadEnabled: vadEnabled,
            removeFillerWords: removeFillerWords,
            learnFromCorrectionsEnabled: learnFromCorrectionsEnabled,
            speechLanguage: speechLanguage,
            translateToEnglish: translateToEnglish,
            muteWhileRecording: muteWhileRecording,
            appearance: appearance.rawValue,
            historyLimit: historyLimit,
            autoDeleteInterval: autoDeleteInterval.rawValue,
            showWhatsNew: showWhatsNew
        )
    }

    /// Applies a pulled snapshot, guarded so the resulting `didSet`s don't re-arm the push
    /// debounce or bump `settingsLastModified` past the remote timestamp.
    func applySyncSnapshot(_ snapshot: SettingsSnapshot, updatedAt: Date) {
        if let data = snapshot.pushToTalkKeyData, let decoded = try? JSONDecoder().decode(PushToTalkKey.self, from: data) {
            pushToTalkKey = decoded
        }
        pushToTalkEnabled = snapshot.pushToTalkEnabled
        engine = SpeechEngineChoice(rawValue: snapshot.engine) ?? engine
        cleanupEnabled = snapshot.cleanupEnabled
        smartCleanup = snapshot.smartCleanup
        soundEnabled = snapshot.soundEnabled
        vadEnabled = snapshot.vadEnabled
        removeFillerWords = snapshot.removeFillerWords
        learnFromCorrectionsEnabled = snapshot.learnFromCorrectionsEnabled
        speechLanguage = snapshot.speechLanguage
        translateToEnglish = snapshot.translateToEnglish
        muteWhileRecording = snapshot.muteWhileRecording
        appearance = AppearanceMode(rawValue: snapshot.appearance) ?? appearance
        historyLimit = snapshot.historyLimit
        autoDeleteInterval = AutoDeleteInterval(rawValue: snapshot.autoDeleteInterval) ?? autoDeleteInterval
        showWhatsNew = snapshot.showWhatsNew
        settingsLastModified = updatedAt
    }
}
