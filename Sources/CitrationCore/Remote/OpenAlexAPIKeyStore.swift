import Foundation
import Security

// MARK: - OpenAlexAPIKeyStore

public protocol OpenAlexAPIKeyStore: Sendable {
    func loadAPIKey() async -> String?
    func saveAPIKey(_ apiKey: String?) async
}

// MARK: - InMemoryOpenAlexAPIKeyStore

public actor InMemoryOpenAlexAPIKeyStore: OpenAlexAPIKeyStore {
    // MARK: Lifecycle

    public init(apiKey: String? = nil) {
        self.apiKey = Self.normalizedAPIKey(apiKey)
    }

    // MARK: Public

    public func loadAPIKey() -> String? {
        apiKey
    }

    public func saveAPIKey(_ apiKey: String?) {
        self.apiKey = Self.normalizedAPIKey(apiKey)
    }

    // MARK: Private

    private var apiKey: String?

    private static func normalizedAPIKey(_ apiKey: String?) -> String? {
        guard
            let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            return nil
        }
        return apiKey
    }
}

// MARK: - KeychainOpenAlexAPIKeyStore

public actor KeychainOpenAlexAPIKeyStore: OpenAlexAPIKeyStore {
    // MARK: Lifecycle

    public init(service: String = "app.citration.openalex", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    // MARK: Public

    public func loadAPIKey() -> String? {
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
            let data = result as? Data,
            let apiKey = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            return nil
        }

        return apiKey
    }

    public func saveAPIKey(_ apiKey: String?) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard
            let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty,
            let data = apiKey.data(using: .utf8)
        else {
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
