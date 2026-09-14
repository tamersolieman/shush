import Foundation
import Observation

/// Cumulative usage counters that survive history deletion — the History Limit, Auto-Delete
/// Recordings, and the manual trash button all remove entries from `RunLog`, but the
/// dashboard's lifetime numbers (total words, streak, desktop usage, …) are meant to keep
/// growing regardless. So this is a separate, append-only record: every recorded run adds to
/// it once and nothing ever subtracts.
struct LifetimeStats: Codable {
    struct AppTally: Codable {
        var name: String
        var bundleID: String?
        var count: Int
    }

    var totalRuns: Int = 0
    var totalWords: Int = 0
    var totalAudioSeconds: Double = 0
    var dictionaryFixes: Int = 0
    var wordsCorrected: Int = 0
    /// Keyed by bundle id (or app name when no bundle id was captured).
    var appTallies: [String: AppTally] = [:]
    /// Keyed by "yyyy-MM-dd" — every recording counts here,
    /// since the streak tracks "were you here" rather than "was text injected".
    var dayCounts: [String: Int] = [:]
    /// Keyed by "yyyy-MM" — injected runs only, for month-over-month.
    var monthWords: [String: Int] = [:]
}

@MainActor
@Observable
final class LifetimeStatsStore {
    static let shared = LifetimeStatsStore()

    private(set) var current: LifetimeStats

    /// The dashboard's actual display value: `current` (this device's own totals) summed with
    /// every other device's last-synced snapshot. Defaults to `current` until a pull ever
    /// completes, so signed-out/never-synced behaves exactly as before this feature existed.
    private(set) var merged: LifetimeStats

    /// The most recent set of other-device snapshots downloaded by `SyncEngine`, kept around so
    /// `record(_:)` can keep `merged` current between pulls without a network round trip.
    private var lastRemoteDevices: [DeviceStatsPayload] = []

    private let defaults = UserDefaults.standard
    private let defaultsKey = "lifetimeStats"

    private init() {
        let loaded: LifetimeStats
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(LifetimeStats.self, from: data) {
            loaded = decoded
        } else {
            loaded = LifetimeStats()
        }
        current = loaded
        merged = loaded
    }

    /// Called by `SyncEngine` after downloading every device's stats file. Never writes back
    /// into `current`/`UserDefaults` — the merge result is a view, not a new local total.
    func applyMerged(remoteDevices: [DeviceStatsPayload]) {
        lastRemoteDevices = remoteDevices
        merged = Self.merge(local: current, selfDeviceID: DeviceID.value, remoteDevices: remoteDevices)
    }

    /// Folds one completed run into the lifetime totals. Call once per run, at the point
    /// it's recorded — never on delete, trim, or clear.
    func record(_ run: DictationRun) {
        var stats = current
        stats.totalRuns += 1

        let calendar = Calendar.current
        stats.dayCounts[Self.dayKey(run.date, calendar: calendar), default: 0] += 1

        stats.totalWords += run.wordCount
        stats.totalAudioSeconds += run.audioSeconds
        stats.dictionaryFixes += run.corrections?.count ?? 0
        stats.wordsCorrected += run.corrections?.reduce(0) { $0 + $1.count } ?? 0
        stats.monthWords[Self.monthKey(run.date, calendar: calendar), default: 0] += run.wordCount

        if let name = run.appName {
            let id = run.appBundleID ?? name
            var tally = stats.appTallies[id] ?? LifetimeStats.AppTally(name: name, bundleID: run.appBundleID, count: 0)
            tally.count += 1
            stats.appTallies[id] = tally
        }

        current = stats
        merged = Self.merge(local: stats, selfDeviceID: DeviceID.value, remoteDevices: lastRemoteDevices)
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: defaultsKey)
        SyncEngine.shared.scheduleStatsPush()
    }

    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    nonisolated static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// Inverse of `dayKey` — for rebuilding a `Date` from the persisted string key.
    nonisolated static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        return calendar.date(from: comps)
    }
}
