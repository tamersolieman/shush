import Foundation

/// A stable per-install identifier, used to name this machine's own stats file in Drive
/// (`stats-{deviceID}.json`) so lifetime stats can merge additively across machines instead of
/// last-write-wins clobbering one machine's totals with another's. Lives in the Keychain,
/// not `Settings`/`UserDefaults`: it must survive a `defaults delete`, and — unlike a normal
/// setting — must NOT roam via iCloud Keychain, since two Macs sharing one ID would collapse
/// the per-device split this exists for.
enum DeviceID {
    private static let service = "ai.pivotstudio.shush.sync"
    private static let account = "deviceID"

    static let value: String = {
        if let data = KeychainStore.load(service: service, account: account),
           let existing = String(data: data, encoding: .utf8) {
            return existing
        }
        let generated = UUID().uuidString
        if let data = generated.data(using: .utf8) {
            KeychainStore.save(data, service: service, account: account)
        }
        return generated
    }()
}
