import AppKit
import CryptoKit
import Foundation
import Network
import ShushDictionary

/// Keeps Settings, the Dictionary, Snippets, transcripts and lifetime stats in step across
/// Macs through Drive's `appDataFolder`.
///
/// Every cycle compares each item with its Drive copy and moves data whichever way it has to
/// go, instead of only pushing when something is edited and only pulling on a timer. That is
/// what makes it self-healing: an edit that couldn't be pushed (offline, signed out, the app
/// quit inside the debounce window) stays marked dirty and goes out on the next cycle, and a
/// Mac that missed a change catches up on wake, on reconnect, on activation and every few
/// minutes. See `SyncDecision` for how direction is chosen.
@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum Kind: String, CaseIterable {
        case settings, dictionary, snippets, stats, runs
    }

    /// Set while applying a pulled value back into `Settings`, so the resulting local writes
    /// don't look like a fresh edit and re-arm a push right back to Drive.
    private(set) var isApplyingRemote = false

    private let drive = DriveClient()
    private let defaults = UserDefaults.standard

    private var cycleTimer: Task<Void, Never>?
    private var pushTasks: [Kind: Task<Void, Never>] = [:]
    private var isRunning = false
    private var queued: Set<Kind> = []
    private var failures: [Kind: String] = [:]

    private var triggersInstalled = false
    private var pathMonitor: NWPathMonitor?
    private var hasSeenFirstPath = false
    private var lastActivationSync = Date.distantPast

    private static let debounceInterval: Duration = .seconds(3)
    private static let cycleInterval: Duration = .seconds(300)
    private static let activationThrottle: TimeInterval = 60

    private init() {}

    // MARK: - Lifecycle

    /// Call once at launch. No-op until the user has signed in and turned sync on; each cycle
    /// re-checks, so toggling either off just stops the next cycle.
    func start() {
        installTriggers()
        Task { await syncNow() }
        cycleTimer?.cancel()
        cycleTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.cycleInterval)
                await self?.syncNow()
            }
        }
    }

    /// The Account section's "Sync Now" button, and what every trigger below calls.
    func syncNow() async {
        await reconcile(Set(Kind.allCases))
    }

    /// Things that mean the Drive copy may have moved, or that a failed attempt can now work.
    private func installTriggers() {
        guard !triggersInstalled else { return }
        triggersInstalled = true

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await SyncEngine.shared.syncNow() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await SyncEngine.shared.syncOnActivation() }
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let isUp = path.status == .satisfied
            Task { @MainActor in await SyncEngine.shared.networkChanged(isUp: isUp) }
        }
        monitor.start(queue: DispatchQueue(label: "ai.pivotstudio.shush.sync.path"))
        pathMonitor = monitor
    }

    private func syncOnActivation() async {
        guard Date().timeIntervalSince(lastActivationSync) > Self.activationThrottle else { return }
        lastActivationSync = .now
        await syncNow()
    }

    /// The monitor reports the current state as soon as it starts; `start()` already syncs,
    /// so only a *later* "network is up" is news.
    private func networkChanged(isUp: Bool) async {
        guard hasSeenFirstPath else {
            hasSeenFirstPath = true
            return
        }
        if isUp { await syncNow() }
    }

    // MARK: - Change tracking

    /// Called by each store when its data changes. The dirty flag is recorded even while
    /// signed out or paused, so those edits go out as soon as sync is back.
    private func noteChange(_ kind: Kind) {
        setDirty(true, kind)
        guard isEnabled else { return }
        pushTasks[kind]?.cancel()
        pushTasks[kind] = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.reconcile([kind])
        }
    }

    func scheduleSettingsPush() { noteChange(.settings) }
    func scheduleDictionaryPush() { noteChange(.dictionary) }
    func scheduleSnippetsPush() { noteChange(.snippets) }
    func scheduleStatsPush() { noteChange(.stats) }
    func scheduleRunsPush() { noteChange(.runs) }

    private var isEnabled: Bool {
        Settings.shared.syncEnabled && GoogleAuthService.shared.isSignedIn
    }

    private func key(_ kind: Kind, _ field: String) -> String { "sync.\(kind.rawValue).\(field)" }
    private func lastSeen(_ kind: Kind) -> Date? { defaults.object(forKey: key(kind, "lastSeen")) as? Date }
    private func setLastSeen(_ date: Date, _ kind: Kind) { defaults.set(date, forKey: key(kind, "lastSeen")) }
    private func isDirty(_ kind: Kind) -> Bool { defaults.bool(forKey: key(kind, "dirty")) }
    private func setDirty(_ flag: Bool, _ kind: Kind) { defaults.set(flag, forKey: key(kind, "dirty")) }

    private static func wholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    // MARK: - Reconcile

    /// One pass over `kinds`. A call that arrives mid-pass folds into it rather than running
    /// alongside, so two triggers firing together never race each other against Drive.
    func reconcile(_ kinds: Set<Kind>) async {
        guard Settings.shared.syncEnabled else { return }

        let auth = GoogleAuthService.shared
        auth.restoreIfNeeded()
        guard auth.isSignedIn else {
            if auth.needsReconnect { Settings.shared.lastSyncError = SyncError.tokenExpired.errorDescription }
            return
        }

        queued.formUnion(kinds)
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        while !queued.isEmpty {
            let batch = queued
            queued = []
            for kind in Kind.allCases where batch.contains(kind) {
                do {
                    try await reconcile(kind)
                    failures[kind] = nil
                } catch SyncError.tokenExpired {
                    failures[kind] = SyncError.tokenExpired.errorDescription
                    queued = []
                    break
                } catch {
                    Log.sync.error("sync \(kind.rawValue, privacy: .public) failed: \(error.localizedDescription)")
                    failures[kind] = error.localizedDescription
                }
            }
        }

        Settings.shared.lastSyncError = failures.values.first
        if failures.isEmpty { Settings.shared.lastSyncDate = .now }
    }

    private func reconcile(_ kind: Kind) async throws {
        switch kind {
        case .settings: try await reconcileSettings()
        case .dictionary: try await reconcileDictionary()
        case .snippets: try await reconcileSnippets()
        case .stats: try await reconcileStats()
        case .runs: try await reconcileRuns()
        }
    }

    /// Clears the dirty flag *before* the payload is built and sent, so an edit made while the
    /// upload is in flight re-marks it instead of being wiped by this push succeeding. A
    /// failed upload puts the flag back, which is what makes the next cycle retry it.
    private func push(_ kind: Kind, stamp: Date, upload: () async throws -> Void) async throws {
        setDirty(false, kind)
        do {
            try await upload()
            setLastSeen(stamp, kind)
        } catch {
            setDirty(true, kind)
            throw error
        }
    }

    // MARK: Settings

    private func reconcileSettings() async throws {
        let settings = Settings.shared
        let remote = try await drive.download(SettingsPayload.self, name: "settings.json")
        let action = SyncDecision.decide(
            remote: remote?.updatedAt,
            lastSeen: lastSeen(.settings),
            dirty: isDirty(.settings),
            hasLocal: settings.settingsLastModified > .distantPast
        )

        switch action {
        case .none:
            return
        case .pull:
            if let remote { applySettings(remote) }
        case .push:
            try await pushSettings()
        case .merge:
            // Settings are single values with nothing to union, so the newer write wins.
            if let remote, remote.updatedAt > settings.settingsLastModified {
                applySettings(remote)
            } else {
                try await pushSettings()
            }
        }
    }

    private func applySettings(_ remote: SettingsPayload) {
        isApplyingRemote = true
        Settings.shared.applySyncSnapshot(remote.settings, updatedAt: remote.updatedAt)
        isApplyingRemote = false
        setLastSeen(remote.updatedAt, .settings)
        setDirty(false, .settings)
    }

    private func pushSettings() async throws {
        let stamp = Self.wholeSecond(Settings.shared.settingsLastModified)
        try await push(.settings, stamp: stamp) {
            let payload = SettingsPayload(updatedAt: stamp, deviceID: DeviceID.value, settings: Settings.shared.syncSnapshot())
            try await drive.upload(payload, name: "settings.json")
        }
    }

    // MARK: Dictionary

    private func reconcileDictionary() async throws {
        let store = DictionaryStore.shared
        let remote = try await drive.download(DictionaryPayload.self, name: "dictionary.json")
        let action = SyncDecision.decide(
            remote: remote?.updatedAt,
            lastSeen: lastSeen(.dictionary),
            dirty: isDirty(.dictionary),
            hasLocal: store.hasFile
        )

        switch action {
        case .none:
            return
        case .pull:
            guard let remote else { return }
            store.applyRemote(text: remote.fileText)
            setLastSeen(remote.updatedAt, .dictionary)
            setDirty(false, .dictionary)
        case .push:
            try await pushDictionary()
        case .merge:
            if let remote { store.merge(remoteText: remote.fileText) }
            try await pushDictionary()
        }
    }

    private func pushDictionary() async throws {
        let stamp = Self.wholeSecond(.now)
        try await push(.dictionary, stamp: stamp) {
            let text = DictionaryStore.shared.entries.map(\.fileLine).joined(separator: "\n")
            let payload = DictionaryPayload(updatedAt: stamp, deviceID: DeviceID.value, fileText: text)
            try await drive.upload(payload, name: "dictionary.json")
        }
    }

    // MARK: Snippets

    private func reconcileSnippets() async throws {
        let store = SnippetStore.shared
        let remote = try await drive.download(SnippetsPayload.self, name: "snippets.json")
        let action = SyncDecision.decide(
            remote: remote?.updatedAt,
            lastSeen: lastSeen(.snippets),
            dirty: isDirty(.snippets),
            hasLocal: store.hasFile
        )

        switch action {
        case .none:
            return
        case .pull:
            guard let remote else { return }
            store.applyRemote(remote.snippets)
            setLastSeen(remote.updatedAt, .snippets)
            setDirty(false, .snippets)
        case .push:
            try await pushSnippets()
        case .merge:
            // Both sides edited: keep every cue from either, and this Mac's text where both
            // have the same cue.
            if let remote { store.applyRemote(SnippetFile.merge(store.snippets, into: remote.snippets)) }
            try await pushSnippets()
        }
    }

    private func pushSnippets() async throws {
        let stamp = Self.wholeSecond(.now)
        try await push(.snippets, stamp: stamp) {
            let payload = SnippetsPayload(updatedAt: stamp, deviceID: DeviceID.value, snippets: SnippetStore.shared.snippets)
            try await drive.upload(payload, name: "snippets.json")
        }
    }

    // MARK: Stats

    /// Stats never conflict: each Mac only ever writes its own file and the dashboard sums
    /// them. So this is "publish mine if it changed, then read everyone's".
    private func reconcileStats() async throws {
        let store = LifetimeStatsStore.shared
        if isDirty(.stats) || (lastSeen(.stats) == nil && store.current.totalRuns > 0) {
            try await pushStats()
        }

        let devices = try await drive.downloadAllStats()
        // Counters only ever grow, so a bigger copy of *this* Mac's file on Drive means local
        // data was lost (reset defaults, restored backup). Take it back rather than later
        // overwriting it with the smaller numbers.
        if let mine = devices.first(where: { $0.deviceID == DeviceID.value }) {
            store.adoptIfBehind(mine.stats)
        }
        store.applyMerged(remoteDevices: devices)
    }

    private func pushStats() async throws {
        let stamp = Self.wholeSecond(.now)
        try await push(.stats, stamp: stamp) {
            let payload = DeviceStatsPayload(deviceID: DeviceID.value, updatedAt: stamp, stats: LifetimeStatsStore.shared.current)
            try await drive.uploadStats(payload)
        }
    }

    // MARK: Transcripts

    /// Same shape as stats: publish this Mac's history if it changed, then read the others'.
    /// "Changed" is the dirty flag *or* a different set of run ids than last published, because
    /// retention trims history at launch without going through any change hook.
    private func reconcileRuns() async throws {
        let signatureKey = key(.runs, "signature")
        let published = defaults.string(forKey: signatureKey) ?? Self.signature([])
        if isDirty(.runs) || Self.signature(RunLog.load()) != published {
            try await pushRuns(signatureKey: signatureKey)
        }

        let devices = try await drive.downloadAllRuns()
        RunStore.shared.setRemote(devices.filter { $0.deviceID != DeviceID.value }.flatMap(\.runs))
    }

    private func pushRuns(signatureKey: String) async throws {
        let stamp = Self.wholeSecond(.now)
        try await push(.runs, stamp: stamp) {
            let runs = RunLog.load()
            try await drive.uploadRuns(DeviceRunsPayload(deviceID: DeviceID.value, updatedAt: stamp, runs: runs))
            defaults.set(Self.signature(runs), forKey: signatureKey)
        }
    }

    /// Order-independent digest of which runs exist. Stable across launches, unlike `hashValue`.
    private static func signature(_ runs: [DictationRun]) -> String {
        let ids = runs.map(\.id.uuidString).sorted().joined()
        return SHA256.hash(data: Data(ids.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
