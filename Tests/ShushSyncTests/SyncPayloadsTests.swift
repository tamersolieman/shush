import Testing
import Foundation
@testable import Shush

@Suite("Sync payload codecs")
struct SyncPayloadCodecTests {
    @Test("SettingsPayload round trips through JSON")
    func settingsRoundTrip() throws {
        let snapshot = SettingsSnapshot(
            pushToTalkKeyData: Data([1, 2, 3]),
            pushToTalkEnabled: true,
            engine: "apple",
            compareMode: false,
            cleanupEnabled: true,
            smartCleanup: false,
            soundEnabled: true,
            vadEnabled: true,
            removeFillerWords: true,
            learnFromCorrectionsEnabled: false,
            speechLanguage: "auto",
            translateToEnglish: false,
            muteWhileRecording: false,
            appearance: "system",
            historyLimit: 10,
            autoDeleteInterval: "threeDays",
            showWhatsNew: true
        )
        let payload = SettingsPayload(updatedAt: .now, deviceID: "device-1", settings: snapshot)

        let data = try JSONEncoder.sync.encode(payload)
        let decoded = try JSONDecoder.sync.decode(SettingsPayload.self, from: data)

        #expect(decoded.deviceID == payload.deviceID)
        #expect(decoded.settings.engine == "apple")
        #expect(decoded.settings.historyLimit == 10)
    }

    @Test("DictionaryPayload round trips through JSON")
    func dictionaryRoundTrip() throws {
        let payload = DictionaryPayload(updatedAt: .now, deviceID: "device-1", fileText: "Anthropic\ncloud code -> Claude Code\n")
        let data = try JSONEncoder.sync.encode(payload)
        let decoded = try JSONDecoder.sync.decode(DictionaryPayload.self, from: data)
        #expect(decoded.fileText == payload.fileText)
    }

    @Test("DeviceStatsPayload round trips through JSON, including nested LifetimeStats")
    func statsRoundTrip() throws {
        var stats = LifetimeStats()
        stats.totalRuns = 5
        stats.dayCounts["2026-09-13"] = 2
        let payload = DeviceStatsPayload(deviceID: "device-1", updatedAt: .now, stats: stats)

        let data = try JSONEncoder.sync.encode(payload)
        let decoded = try JSONDecoder.sync.decode(DeviceStatsPayload.self, from: data)

        #expect(decoded.stats.totalRuns == 5)
        #expect(decoded.stats.dayCounts["2026-09-13"] == 2)
    }
}

@Suite("PKCE code challenge")
struct PKCETests {
    // Fixed verifier/challenge pair from RFC 7636 Appendix B.
    @Test("matches the RFC 7636 worked example")
    func rfcExample() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = GoogleAuthService.codeChallenge(for: verifier)
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
}

@Suite("Lifetime stats merge")
struct LifetimeStatsMergeTests {
    @Test("single device: merged equals local")
    func singleDevice() {
        var local = LifetimeStats()
        local.totalRuns = 3
        local.totalWords = 100
        local.dayCounts["2026-09-13"] = 3

        let merged = LifetimeStatsStore.merge(local: local, selfDeviceID: "self", remoteDevices: [])

        #expect(merged.totalRuns == 3)
        #expect(merged.totalWords == 100)
        #expect(merged.dayCounts["2026-09-13"] == 3)
    }

    @Test("two devices: overlapping keys add rather than overwrite")
    func twoDevicesAdditive() {
        var local = LifetimeStats()
        local.totalRuns = 3
        local.totalWords = 100
        local.dayCounts["2026-09-13"] = 3
        local.appTallies["com.apple.mail"] = .init(name: "Mail", bundleID: "com.apple.mail", count: 2)

        var other = LifetimeStats()
        other.totalRuns = 5
        other.totalWords = 200
        other.dayCounts["2026-09-13"] = 1
        other.appTallies["com.apple.mail"] = .init(name: "Mail", bundleID: "com.apple.mail", count: 4)

        let payload = DeviceStatsPayload(deviceID: "other", updatedAt: .now, stats: other)
        let merged = LifetimeStatsStore.merge(local: local, selfDeviceID: "self", remoteDevices: [payload])

        #expect(merged.totalRuns == 8)
        #expect(merged.totalWords == 300)
        #expect(merged.dayCounts["2026-09-13"] == 4)
        #expect(merged.appTallies["com.apple.mail"]?.count == 6)
    }

    @Test("a stale copy of self's own file in the remote list is excluded, not double-counted")
    func excludesSelf() {
        var local = LifetimeStats()
        local.totalRuns = 10

        // Simulates a just-pushed self snapshot that hasn't propagated away yet, and would
        // double the count if not skipped.
        let staleSelf = DeviceStatsPayload(deviceID: "self", updatedAt: .now, stats: local)
        let merged = LifetimeStatsStore.merge(local: local, selfDeviceID: "self", remoteDevices: [staleSelf])

        #expect(merged.totalRuns == 10)
    }
}
