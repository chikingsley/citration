import Foundation
import CitrationCore

protocol OpenAlexAPIKeyProviding: Sendable {
    func apiKey() async -> String?
}

struct StaticOpenAlexAPIKeyProvider: OpenAlexAPIKeyProviding {
    private let value: String?

    init(_ value: String?) {
        self.value = value?.bcTrimmedNonEmpty
    }

    func apiKey() async -> String? {
        value
    }
}

struct OpenAlexCredentialSource: OpenAlexAPIKeyProviding {
    private let keyStore: any OpenAlexAPIKeyStore
    private let environment: [String: String]

    init(
        keyStore: any OpenAlexAPIKeyStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.keyStore = keyStore
        self.environment = environment
    }

    func apiKey() async -> String? {
        if let keychainKey = await keyStore.loadAPIKey() {
            return keychainKey
        }

        return environment["OPENALEX_API_KEY"]?.bcTrimmedNonEmpty
    }
}
