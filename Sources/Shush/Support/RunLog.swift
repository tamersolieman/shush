import ShushDictionary
import Foundation
import Observation

/// One completed dictation.
struct DictationRun: Codable, Sendable, Identifiable {
    /// Stable identity, so a single run can be deleted without matching on its text.
    ///
    /// Decoded leniently: runs written before this existed have no `id` field, and failing
    /// their whole line would throw away the user's history to add a delete button. Those
    /// get a fresh id on load, which is then persisted the next time the file is rewritten.
    var id: UUID = UUID()

    let date: Date
    let engine: String
    /// How long the key was held.
    let audioSeconds: Double
    /// Release → final text ready. This is the latency you actually feel.
    let processSeconds: Double
    let text: String

    /// Dictionary corrections that fired on this transcript. Recorded so history can show
    /// whether the dictionary is actually doing anything, rather than leaving it to faith.
    ///
    /// Optional for backwards compatibility: runs recorded before the dictionary existed
    /// decode with this nil rather than failing the whole line.
    var corrections: [AppliedCorrection]?

    /// The app that received the text — captured from the frontmost app right before
    /// injection. Nil for runs recorded before this existed.
    var appName: String?
    var appBundleID: String?

    var realtimeFactor: Double { audioSeconds / max(processSeconds, 0.0001) }
    var characters: Int { text.count }
    var wordCount: Int { text.split { $0.isWhitespace }.count }

    init(
        id: UUID = UUID(),
        date: Date,
        engine: String,
        audioSeconds: Double,
        processSeconds: Double,
        text: String,
        corrections: [AppliedCorrection]? = nil,
        appName: String? = nil,
        appBundleID: String? = nil
    ) {
        self.id = id
        self.date = date
        self.engine = engine
        self.audioSeconds = audioSeconds
        self.processSeconds = processSeconds
        self.text = text
        self.corrections = corrections
        self.appName = appName
        self.appBundleID = appBundleID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        engine = try container.decode(String.self, forKey: .engine)
        audioSeconds = try container.decode(Double.self, forKey: .audioSeconds)
        processSeconds = try container.decode(Double.self, forKey: .processSeconds)
        text = try container.decode(String.self, forKey: .text)
        corrections = try container.decodeIfPresent([AppliedCorrection].self, forKey: .corrections)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        appBundleID = try container.decodeIfPresent(String.self, forKey: .appBundleID)
    }
}

/// Live-updating store behind the dashboard and transcript history views.
///
/// `runs` is what the views show: this Mac's history plus the other Macs' (read from Drive by
/// `SyncEngine`), oldest first. Only `localRuns` is ever written to disk or published; other
/// Macs' runs are a read-only view, so each Mac stays the sole owner of its own history.
@MainActor
@Observable
final class RunStore {
    static let shared = RunStore()

    private(set) var runs: [DictationRun] = []
    private(set) var localRuns: [DictationRun] = []
    private var remoteRuns: [DictationRun] = []

    private static let hiddenKey = "hiddenRemoteRunIDs"
    private static var remoteCacheURL: URL { RunLog.directory.appendingPathComponent("remote-runs.json") }

    private init() {
        remoteRuns = Self.loadRemoteCache()
        localRuns = RunLog.load()
        rebuild()
    }

    /// Every change to this Mac's history ends here, which makes it the one place that tells
    /// sync the published copy is stale.
    func reload() {
        localRuns = RunLog.load()
        rebuild()
        SyncEngine.shared.scheduleRunsPush()
    }

    /// The other Macs' runs, as last read from Drive. Cached on disk so they're there at
    /// launch before the first sync finishes.
    func setRemote(_ runs: [DictationRun]) {
        remoteRuns = runs
        Self.saveRemoteCache(runs)
        // A hidden id only matters while some Mac still publishes that run.
        let present = Set(runs.map(\.id))
        setHidden(hiddenIDs.filter { present.contains($0) })
        rebuild()
    }

    /// Deleting a run that another Mac recorded can only hide it here: that Mac owns the run,
    /// and removing it there is that Mac's decision.
    func hide(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        setHidden(hiddenIDs.union(ids))
        rebuild()
    }

    func hideAllRemote() {
        hide(Set(remoteRuns.map(\.id)))
    }

    private var hiddenIDs: Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []).compactMap(UUID.init))
    }

    private func setHidden(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: Self.hiddenKey)
    }

    private func rebuild() {
        runs = Self.merge(
            local: localRuns,
            remote: remoteRuns,
            hidden: hiddenIDs,
            limit: Settings.shared.historyLimit,
            maxAge: Settings.shared.autoDeleteInterval.maxAge
        )
    }

    /// Oldest first. The same run can appear on both sides (a Mac reading back its own
    /// published copy), so it's de-duplicated by id, local copy first.
    nonisolated static func merge(
        local: [DictationRun],
        remote: [DictationRun],
        hidden: Set<UUID>,
        limit: Int,
        maxAge: TimeInterval?,
        now: Date = .now
    ) -> [DictationRun] {
        var seen = Set<UUID>()
        var merged = (local + remote).filter { !hidden.contains($0.id) && seen.insert($0.id).inserted }
        if let maxAge {
            let cutoff = now.addingTimeInterval(-maxAge)
            merged = merged.filter { $0.date >= cutoff }
        }
        merged.sort { $0.date < $1.date }
        if limit > 0, merged.count > limit { merged = Array(merged.suffix(limit)) }
        return merged
    }

    private static func loadRemoteCache() -> [DictationRun] {
        guard let data = try? Data(contentsOf: remoteCacheURL) else { return [] }
        return (try? JSONDecoder.sync.decode([DictationRun].self, from: data)) ?? []
    }

    private static func saveRemoteCache(_ runs: [DictationRun]) {
        guard let data = try? JSONEncoder.sync.encode(runs) else { return }
        try? data.write(to: remoteCacheURL, options: .atomic)
    }
}

/// Appends every dictation to a JSONL file and regenerates a dashboard beside it.
///
/// The dashboard is a plain file with a meta-refresh rather than a served page: `file://`
/// can't fetch its own data directory without tripping CORS, so instead of the page pulling
/// data, the app pushes a freshly rendered page after each run and the browser just reloads.
@MainActor
enum RunLog {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shush", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var dashboardURL: URL { directory.appendingPathComponent("dashboard.html") }
    private static var runsURL: URL { directory.appendingPathComponent("runs.jsonl") }

    static func record(_ run: DictationRun) {
        append(run)
        LifetimeStatsStore.shared.record(run)
        regenerate()
        RunStore.shared.reload()
    }

    static func record(_ runs: [DictationRun]) {
        runs.forEach {
            append($0)
            LifetimeStatsStore.shared.record($0)
        }
        regenerate()
        RunStore.shared.reload()
    }

    private static func append(_ run: DictationRun) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(run) else { return }
        line.append(0x0A) // newline

        if let handle = try? FileHandle(forWritingTo: runsURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: runsURL)
        }
    }

    static func load() -> [DictationRun] {
        guard let data = try? Data(contentsOf: runsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(DictationRun.self, from: Data(line))
        }
    }

    static func regenerate() {
        enforceRetention()
        let runs = load()
        try? DashboardHTML.render(
            runs: runs,
            key: Settings.shared.pushToTalkKey.displayName
        ).write(to: dashboardURL, atomically: true, encoding: .utf8)
    }

    /// Deletes one run.
    static func delete(_ run: DictationRun) {
        delete(ids: [run.id])
    }

    static func delete(ids: Set<UUID>) {
        let local = load()
        rewrite(local.filter { !ids.contains($0.id) })
        // Anything not in this Mac's own file came from another Mac, and can only be hidden.
        RunStore.shared.hide(ids.subtracting(local.map(\.id)))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: runsURL)
        RunStore.shared.hideAllRemote()
        regenerate()
        RunStore.shared.reload()
    }

    /// Replaces the whole file. Deleting can't be an append, and rewriting also persists the
    /// ids that older runs were assigned on load.
    private static func rewrite(_ runs: [DictationRun]) {
        writeLines(runs)
        regenerate()
        RunStore.shared.reload()
    }

    private static func writeLines(_ runs: [DictationRun]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let body = runs.compactMap { run -> String? in
            guard let data = try? encoder.encode(run) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")

        // Atomic: a partial write here would lose history that the user didn't ask to delete.
        try? (body.isEmpty ? "" : body + "\n")
            .write(to: runsURL, atomically: true, encoding: .utf8)
    }

    /// Purges entries past `Settings.autoDeleteInterval`, then trims down to
    /// `Settings.historyLimit` most-recent entries. Runs before every dashboard regenerate,
    /// so it applies on launch as well as after each new run.
    private static func enforceRetention() {
        var runs = load()
        let before = runs.count

        if let maxAge = Settings.shared.autoDeleteInterval.maxAge {
            let cutoff = Date().addingTimeInterval(-maxAge)
            runs = runs.filter { $0.date >= cutoff }
        }

        let limit = Settings.shared.historyLimit
        if limit > 0, runs.count > limit {
            runs = Array(runs.suffix(limit))
        }

        guard runs.count != before else { return }
        writeLines(runs)
    }
}
