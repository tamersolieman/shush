import Foundation

enum SyncError: LocalizedError {
    case notSignedIn
    case oauthCallbackInvalid
    case tokenExpired
    case driveAPI(status: Int, message: String)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Not signed in"
        case .oauthCallbackInvalid: "Sign-in was cancelled or interrupted"
        case .tokenExpired: "Google access was revoked — please reconnect"
        case .driveAPI(let status, let message): "Drive error \(status): \(message)"
        case .decodeFailed: "Couldn't read data from Drive"
        }
    }
}

/// The subset of `Settings` that's account-level rather than machine-local — excludes things
/// like `microphoneDeviceID`, a CoreAudio device UID meaningless on another Mac.
struct SettingsSnapshot: Codable {
    var pushToTalkKeyData: Data?
    var pushToTalkEnabled: Bool
    var engine: String
    var cleanupEnabled: Bool
    var smartCleanup: Bool
    var soundEnabled: Bool
    var vadEnabled: Bool
    var removeFillerWords: Bool
    var learnFromCorrectionsEnabled: Bool
    var speechLanguage: String
    var translateToEnglish: Bool
    var muteWhileRecording: Bool
    var appearance: String
    var historyLimit: Int
    var autoDeleteInterval: String
    var showWhatsNew: Bool
}

struct SettingsPayload: Codable {
    var updatedAt: Date
    var deviceID: String
    var settings: SettingsSnapshot
}

struct DictionaryPayload: Codable {
    var updatedAt: Date
    var deviceID: String
    var fileText: String
}

struct DeviceStatsPayload: Codable {
    var deviceID: String
    var updatedAt: Date
    var stats: LifetimeStats
}

extension LifetimeStatsStore {
    /// Sums `local` (this device's own live totals) with every other device's last-pushed
    /// snapshot. `local` always wins for `selfDeviceID`'s slot even if a stale copy of it also
    /// appears in `remoteDevices` — e.g. right after a push, before it's re-downloaded — so a
    /// device's own runs are counted exactly once, never zero and never twice.
    nonisolated static func merge(
        local: LifetimeStats,
        selfDeviceID: String,
        remoteDevices: [DeviceStatsPayload]
    ) -> LifetimeStats {
        var merged = LifetimeStats()

        func fold(_ stats: LifetimeStats) {
            merged.totalRuns += stats.totalRuns
            merged.totalWords += stats.totalWords
            merged.totalAudioSeconds += stats.totalAudioSeconds
            merged.dictionaryFixes += stats.dictionaryFixes
            merged.wordsCorrected += stats.wordsCorrected
            for (day, count) in stats.dayCounts {
                merged.dayCounts[day, default: 0] += count
            }
            for (month, words) in stats.monthWords {
                merged.monthWords[month, default: 0] += words
            }
            for (id, tally) in stats.appTallies {
                var existing = merged.appTallies[id] ?? .init(name: tally.name, bundleID: tally.bundleID, count: 0)
                existing.count += tally.count
                merged.appTallies[id] = existing
            }
        }

        fold(local)
        for device in remoteDevices where device.deviceID != selfDeviceID {
            fold(device.stats)
        }

        return merged
    }
}
