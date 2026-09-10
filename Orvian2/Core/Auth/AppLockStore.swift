import Foundation
import Security

/// Verrouillage par code à 4 chiffres (stocké haché) + biométrie.
enum AppLockStore {
    private static let keychainService = "com.orvian2.app.applock"
    private static let keychainAccount = "lock-code"
    private static let fallbackKey = "orvian2.applock.fallback"

    static var isConfigured: Bool { storedHash != nil }

    static func verify(_ code: String) -> Bool {
        guard let stored = storedHash else { return false }
        return stored == TokenStore.fingerprint(of: code)
    }

    static func save(_ code: String) {
        let hash = TokenStore.fingerprint(of: code)
        if !writeKeychain(hash) {
            UserDefaults.standard.set(hash, forKey: fallbackKey)
        } else {
            UserDefaults.standard.removeObject(forKey: fallbackKey)
        }
    }

    static func clear() {
        deleteKeychain()
        UserDefaults.standard.removeObject(forKey: fallbackKey)
    }

    private static var storedHash: String? {
        readKeychain() ?? UserDefaults.standard.string(forKey: fallbackKey)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeKeychain(_ value: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess { return true }
        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
