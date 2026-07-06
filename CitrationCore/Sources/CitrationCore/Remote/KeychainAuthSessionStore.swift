import Foundation
import Security

public actor KeychainAuthSessionStore: AuthSessionStore {
    // MARK: Lifecycle

    public init(service: String = "app.citration.auth", account: String = "session") {
        self.service = service
        self.account = account
    }

    // MARK: Public

    public func loadSession() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard
            status == errSecSuccess,
            let data = result as? Data
        else {
            return nil
        }

        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func saveSession(_ session: AuthSession?) {
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let session else {
            return
        }

        guard let data = try? JSONEncoder().encode(session) else {
            return
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: Private

    private let service: String
    private let account: String
}
