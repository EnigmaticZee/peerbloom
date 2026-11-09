import Foundation
import Security

/// Stores secrets in the macOS Keychain instead of the preferences file.
enum Keychain {
    private static let service = "app.peerbloom.Peerbloom.proxy"

    /// The proxy password. Setting an empty string removes it.
    static var proxyPassword: String {
        get {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
        set {
            SecItemDelete(baseQuery as CFDictionary)
            guard !newValue.isEmpty else { return }
            var item = baseQuery
            item[kSecValueData as String] = Data(newValue.utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "proxy"]
    }
}
