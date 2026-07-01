import Foundation
import Security

/// Persistent key/value store. Non-secret values go to UserDefaults (like Android's
/// SharedPreferences); the SSH password and Claude key go to the Keychain.
enum Store {
    private static let secretKeys: Set<String> = ["ssh_pass", "claude_key"]
    private static let defaults = UserDefaults.standard

    static func get(_ key: String, _ def: String) -> String {
        if secretKeys.contains(key) { return keychainGet(key) ?? def }
        return defaults.string(forKey: key) ?? def
    }

    static func put(_ key: String, _ value: String) {
        if secretKeys.contains(key) { keychainSet(key, value); return }
        defaults.set(value, forKey: key)
    }

    // ---- Keychain ----

    private static let service = "com.openclaw.clawnest"

    private static func keychainSet(_ key: String, _ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func keychainGet(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
