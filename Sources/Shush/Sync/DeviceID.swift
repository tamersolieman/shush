import Foundation

/// A stable per-install identifier, used to name this machine's own stats file in Drive
/// (`stats-{deviceID}.json`) so lifetime stats can merge additively across machines instead of
/// last-write-wins clobbering one machine's totals with another's. Lives in the Keychain,
/// not `Settings`/`UserDefaults`: it must survive a `defaults delete`, and — unlike a normal
/// setting — must NOT roam via iCloud Keychain, since two Macs sharing one ID would collapse
/// the per-device split this exists for.
///
/// A copy is mirrored in `UserDefaults` purely as a fallback for an unreadable Keychain
/// (locked, or an item written by a differently signed build): without it a failed read would
/// mint a second ID, and this Mac's lifetime stats would then be counted under both.
enum DeviceID {
    private static let service = "ai.pivotstudio.shush.sync"
    private static let account = "deviceID"
    private static let mirrorKey = "deviceIDMirror"

    static let value: String = {
        let defaults = UserDefaults.standard
        if let data = KeychainStore.load(service: service, account: account),
           let existing = String(data: data, encoding: .utf8) {
            defaults.set(existing, forKey: mirrorKey)
            return existing
        }
        let id = defaults.string(forKey: mirrorKey) ?? UUID().uuidString
        defaults.set(id, forKey: mirrorKey)
        if let data = id.data(using: .utf8) {
            KeychainStore.save(data, service: service, account: account)
        }
        return id
    }()
}
