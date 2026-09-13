import Foundation

/// Orchestrates push/pull of Settings, Dictionary, and lifetime stats against Drive's
/// `appDataFolder`. Debounces pushes so rapid edits (e.g. dragging a stepper) don't fire one
/// request per tick, and pulls on launch plus periodically to pick up other machines' changes.
@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    /// Set while applying a pulled value back into `Settings`/`DictionaryStore`, so the
    /// resulting local writes don't look like a fresh edit and re-arm a push right back to
    /// Drive.
    private(set) var isApplyingRemote = false

    private let drive = DriveClient()
    private var pullTimer: Task<Void, Never>?
    private var settingsPushTask: Task<Void, Never>?
    private var dictionaryPushTask: Task<Void, Never>?
    private var statsPushTask: Task<Void, Never>?

    private static let debounceInterval: Duration = .seconds(3)
    private static let pullInterval: Duration = .seconds(600)

    private init() {}

    // MARK: - Lifecycle

    /// Call once at launch. No-op until the user is signed in and has sync on; re-checked on
    /// every timer tick so toggling either off just stops the next cycle rather than needing an
    /// explicit stop() call.
    func start() {
        Task { await pullAll() }
        pullTimer?.cancel()
        pullTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pullInterval)
                await self?.pullAll()
            }
        }
    }

    /// The Account section's "Sync Now" button.
    func syncNow() async {
        await pushSettings()
        await pushDictionary()
        await pushStats()
        await pullAll()
    }

    private var isEnabled: Bool {
        Settings.shared.syncEnabled && GoogleAuthService.shared.isSignedIn
    }

    // MARK: - Push (debounced)

    func scheduleSettingsPush() {
        guard isEnabled else { return }
        settingsPushTask?.cancel()
        settingsPushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.pushSettings()
        }
    }

    func scheduleDictionaryPush() {
        guard isEnabled else { return }
        dictionaryPushTask?.cancel()
        dictionaryPushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.pushDictionary()
        }
    }

    func scheduleStatsPush() {
        guard isEnabled else { return }
        statsPushTask?.cancel()
        statsPushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.pushStats()
        }
    }

    private func pushSettings() async {
        guard isEnabled else { return }
        let payload = SettingsPayload(
            updatedAt: Settings.shared.settingsLastModified,
            deviceID: DeviceID.value,
            settings: Settings.shared.syncSnapshot()
        )
        await run { try await self.drive.upload(payload, name: "settings.json") }
    }

    private func pushDictionary() async {
        guard isEnabled else { return }
        let store = DictionaryStore.shared
        let text = store.entries.map(\.fileLine).joined(separator: "\n")
        let payload = DictionaryPayload(updatedAt: store.lastModified, deviceID: DeviceID.value, fileText: text)
        await run { try await self.drive.upload(payload, name: "dictionary.json") }
    }

    private func pushStats() async {
        guard isEnabled else { return }
        let payload = DeviceStatsPayload(
            deviceID: DeviceID.value,
            updatedAt: .now,
            stats: LifetimeStatsStore.shared.current
        )
        await run { try await self.drive.uploadStats(payload) }
    }

    // MARK: - Pull

    private func pullAll() async {
        guard isEnabled else { return }
        await run { try await self.pullSettings() }
        await run { try await self.pullDictionary() }
        await run { try await self.pullStats() }
        Settings.shared.lastSyncDate = .now
    }

    private func pullSettings() async throws {
        guard let remote = try await drive.download(SettingsPayload.self, name: "settings.json") else { return }
        guard remote.updatedAt > Settings.shared.settingsLastModified else { return }
        isApplyingRemote = true
        Settings.shared.applySyncSnapshot(remote.settings, updatedAt: remote.updatedAt)
        isApplyingRemote = false
    }

    private func pullDictionary() async throws {
        guard let remote = try await drive.download(DictionaryPayload.self, name: "dictionary.json") else { return }
        guard remote.updatedAt > DictionaryStore.shared.lastModified else { return }
        DictionaryStore.shared.applyRemote(text: remote.fileText)
    }

    private func pullStats() async throws {
        let devices = try await drive.downloadAllStats()
        LifetimeStatsStore.shared.applyMerged(remoteDevices: devices)
    }

    // MARK: - Error surfacing

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            Settings.shared.lastSyncError = nil
        } catch {
            Log.sync.error("sync failed: \(error.localizedDescription)")
            Settings.shared.lastSyncError = error.localizedDescription
        }
    }
}
