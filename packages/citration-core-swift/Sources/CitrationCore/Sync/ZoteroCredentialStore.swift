import Foundation

// MARK: - ZoteroCredentialStore

public protocol ZoteroCredentialStore: Sendable {
    func loadCredential() async throws -> String?
    func saveCredential(_ credential: String?) async throws
}

// MARK: - ZoteroCredentialStoreError

public enum ZoteroCredentialStoreError: Error, Equatable, Sendable {
    case unavailable
    case insecurePermissions
}

// MARK: - FileZoteroCredentialStore

public actor FileZoteroCredentialStore: ZoteroCredentialStore {
    // MARK: Lifecycle

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    // MARK: Public

    public func loadCredential() throws -> String? {
        let fileURL = try resolvedFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard
            let permissions = attributes[.posixPermissions] as? NSNumber,
            permissions.intValue & 0o077 == 0
        else {
            throw ZoteroCredentialStoreError.insecurePermissions
        }
        let value = try String(contentsOf: fileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func saveCredential(_ credential: String?) throws {
        let fileURL = try resolvedFileURL()
        let normalized = credential?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try Data(normalized.utf8).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    // MARK: Private

    private let fileURL: URL?

    private static func defaultFileURL() -> URL? {
        try? CitrationCorePaths.applicationSupportDirectory()
            .appending(path: "zotero-device-api-key")
    }

    private func resolvedFileURL() throws -> URL {
        guard let fileURL, fileURL.isFileURL else {
            throw ZoteroCredentialStoreError.unavailable
        }
        return fileURL
    }
}
