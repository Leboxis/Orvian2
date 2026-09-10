import CryptoKit
import Foundation
import Security

/// Stockage du token API : Keychain avec repli UserDefaults (LiveContainer).
/// Aucun secret n'est jamais écrit dans le dépôt.
enum TokenStore {
    private static let keychainService = "com.orvian2.app.api-token"
    private static let keychainAccount = "orvian2"
    private static let fallbackKey = "orvian2.api-token.fallback"

    private static let lock = NSLock()
    private static var cachedToken: String?? = nil

    static func current() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cachedToken { return cached }
        let token = readKeychain() ?? UserDefaults.standard.string(forKey: fallbackKey)
        cachedToken = token
        return token
    }

    @discardableResult
    static func save(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        cachedToken = trimmed
        lock.unlock()
        if !writeKeychain(trimmed) {
            UserDefaults.standard.set(trimmed, forKey: fallbackKey)
        } else {
            UserDefaults.standard.removeObject(forKey: fallbackKey)
        }
        return trimmed
    }

    static func clear() {
        lock.lock()
        cachedToken = .some(nil)
        lock.unlock()
        deleteKeychain()
        UserDefaults.standard.removeObject(forKey: fallbackKey)
    }

    static func credentialFingerprint() -> String? {
        guard let token = current(), !token.isEmpty else { return nil }
        return fingerprint(of: token)
    }

    /// SHA-256 hex minuscule.
    static func fingerprint(of value: String) -> String {
        SHA256.hash(value)
    }

    // MARK: Keychain

    private static func readKeychain() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeKeychain(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
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

/// Petit utilitaire SHA-256 partagé.
enum SHA256 {
    static func hash(_ value: String) -> String {
        let digest = CryptoKit.SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hex(_ data: Data) -> String {
        CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
