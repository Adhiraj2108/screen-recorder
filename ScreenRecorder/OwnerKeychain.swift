import Foundation
import Security

/// Keeps the owner key in the macOS Keychain, never in the app's code, settings files or the repository.
enum OwnerKeychain {
    /// Overridable only so automated tests can use their own entry and never touch the real stored key.
    nonisolated(unsafe) static var service = "local.screenrecorder.app.sharing"
    private static let account = "owner-key"

    private static var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var item = identity
        item[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(identity as CFDictionary)
    }
}
