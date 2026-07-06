import CitrationCore
import Foundation

// MARK: - OpenAlexAPIKeyProviding

protocol OpenAlexAPIKeyProviding: Sendable {
    func apiKey() async -> String?
}

// MARK: - StaticOpenAlexAPIKeyProvider

struct StaticOpenAlexAPIKeyProvider: OpenAlexAPIKeyProviding {
    // MARK: Lifecycle

    init(_ value: String?) {
        self.value = value?.bcTrimmedNonEmpty
    }

    // MARK: Internal

    func apiKey() -> String? {
        value
    }

    // MARK: Private

    private let value: String?
}

// MARK: - OpenAlexCredentialSource

struct OpenAlexCredentialSource: OpenAlexAPIKeyProviding {
    // MARK: Lifecycle

    init(
        keyStore: any OpenAlexAPIKeyStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.keyStore = keyStore
        self.environment = environment
    }

    // MARK: Internal

    func apiKey() async -> String? {
        if let keychainKey = await keyStore.loadAPIKey() {
            return keychainKey
        }

        return environment["OPENALEX_API_KEY"]?.bcTrimmedNonEmpty
    }

    // MARK: Private

    private let keyStore: any OpenAlexAPIKeyStore
    private let environment: [String: String]
}
