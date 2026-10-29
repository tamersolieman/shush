import Foundation
import Security

/// Raw Keychain access for a single generic-password item, keyed by service+account. No
/// wrapper dependency exists in this codebase, and the surface needed here (save/load/delete
/// one JSON blob) is small enough not to warrant one.
enum KeychainStore {
    /// `.afterFirstUnlock` items sync via iCloud Keychain when the user has that on — wrong
    /// for both the OAuth tokens (would let another Mac's Shush install silently inherit this
    /// one's Google session) and the device ID (would defeat the per-device stats split, since
    /// two Macs would end up sharing one ID). Every item this app stores must stay local.
    private nonisolated(unsafe) static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    static func save(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Update in place when the item exists. Delete-then-add loses the token outright if
        // the delete is refused (an item written by a differently signed build) and the add
        // then collides with what's still there.
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        if updated != errSecItemNotFound { SecItemDelete(query as CFDictionary) }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = accessibility
        let added = SecItemAdd(attributes as CFDictionary, nil)
        if added != errSecSuccess {
            Log.sync.error("Keychain save failed for \(account, privacy: .public) (OSStatus \(added, privacy: .public))")
        }
    }

    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.sync.error("Keychain read failed for \(account, privacy: .public) (OSStatus \(status, privacy: .public))")
        }
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
