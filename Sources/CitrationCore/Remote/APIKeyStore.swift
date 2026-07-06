import Foundation

// MARK: - APIKeyStore

public protocol APIKeyStore: Sendable {
    func loadAPIKey() async -> String?
    func saveAPIKey(_ apiKey: String?) async
}

// MARK: - InMemoryAPIKeyStore

public actor InMemoryAPIKeyStore: APIKeyStore {
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

// MARK: - FileAPIKeyStore

/// Stores the OpenAlex API key in a plain 0600 file under Application
/// Support. Deliberately not the Keychain: unsigned debug builds get a
/// fresh keychain identity every rebuild, which makes macOS re-prompt
/// for access each time.
public actor FileAPIKeyStore: APIKeyStore {
    // MARK: Lifecycle

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL(fileName: "openalex-api-key")
    }

    public init(fileName: String) {
        fileURL = Self.defaultFileURL(fileName: fileName)
    }

    // MARK: Public

    public func loadAPIKey() -> String? {
        guard
            let fileURL,
            let raw = try? String(contentsOf: fileURL, encoding: .utf8)
        else {
            return nil
        }

        let apiKey = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return apiKey.isEmpty ? nil : apiKey
    }

    public func saveAPIKey(_ apiKey: String?) {
        guard let fileURL else {
            return
        }

        let normalized = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data(normalized.utf8).write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    // MARK: Private

    private let fileURL: URL?

    private static func defaultFileURL(fileName: String) -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Citration", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
