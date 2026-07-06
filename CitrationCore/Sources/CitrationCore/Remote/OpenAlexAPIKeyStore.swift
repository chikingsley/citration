import Foundation
import Security

public protocol OpenAlexAPIKeyStore: Sendable {
    func loadAPIKey() async -> String?
    func saveAPIKey(_ apiKey: String?) async
}

public actor InMemoryOpenAlexAPIKeyStore: OpenAlexAPIKeyStore {
    private var apiKey: String?

    public init(apiKey: String? = nil) {
        self.apiKey = Self.normalizedAPIKey(apiKey)
    }

    public func loadAPIKey() async -> String? {
        apiKey
    }

    public func saveAPIKey(_ apiKey: String?) async {
        self.apiKey = Self.normalizedAPIKey(apiKey)
    }

    private static func normalizedAPIKey(_ apiKey: String?) -> String? {
        guard let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }
}

public actor KeychainOpenAlexAPIKeyStore: OpenAlexAPIKeyStore {
    private let service: String
    private let account: String

    public init(service: String = "app.citration.openalex", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    public func loadAPIKey() async -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }

        return apiKey
    }

    public func saveAPIKey(_ apiKey: String?) async {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty,
              let data = apiKey.data(using: .utf8) else {
            return
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
