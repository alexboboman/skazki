import Foundation
import Security

/// Keeps the account token in the Keychain, so a guest account survives app restarts.
public final class KeychainSessionStore: SessionStore, @unchecked Sendable {
    private let service: String
    private let account = "api-token"

    public init(service: String = "app.skazochnik.session") {
        self.service = service
    }

    public func loadToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func saveToken(_ token: String?) {
        SecItemDelete(baseQuery() as CFDictionary)
        guard let token, let data = token.data(using: .utf8) else { return }

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
