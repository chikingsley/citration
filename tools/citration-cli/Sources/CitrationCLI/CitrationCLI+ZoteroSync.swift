import CitrationCore
import Foundation

extension CitrationCLI {
    func configureZoteroConnection(arguments: [String]) async throws {
        let server = try requiredValue("--server", arguments: arguments)
        let databasePath = try requiredValue("--database", arguments: arguments)
        guard let serverURL = URL(string: server) else {
            throw CLIInputError.invalidValue("--server")
        }
        let apiKey = try zoteroAPIKey()
        let (database, credentialStore) = try connectionPersistence(
            databasePath: databasePath,
            arguments: arguments
        )
        let profile = try await ZoteroConnectionManager(
            database: database,
            credentialStore: credentialStore
        ).connect(serverURL: serverURL, apiKey: apiKey)
        try printJSON(ConnectionOutput(
            mode: "connected",
            userID: profile.userID,
            canWrite: profile.canWrite,
            canAccessFiles: profile.canAccessFiles,
            integrity: database.integrityCheck()
        ))
    }

    func useLocalOnly(arguments: [String]) async throws {
        let databasePath = try requiredValue("--database", arguments: arguments)
        let (database, credentialStore) = try connectionPersistence(
            databasePath: databasePath,
            arguments: arguments
        )
        try await ZoteroConnectionManager(
            database: database,
            credentialStore: credentialStore
        ).useLocalOnly()
        try printJSON(ConnectionOutput(
            mode: "localOnly",
            userID: nil,
            canWrite: nil,
            canAccessFiles: nil,
            integrity: database.integrityCheck()
        ))
    }

    func syncZoteroReadOnly(arguments: [String]) async throws {
        let server = try requiredValue("--server", arguments: arguments)
        let databasePath = try requiredValue("--database", arguments: arguments)
        guard let serverURL = URL(string: server) else {
            throw CLIInputError.invalidValue("--server")
        }
        let apiKey = try zoteroAPIKey()

        let databaseURL = URL(filePath: databasePath)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let database = try CitrationDatabase(at: databaseURL)
        let connection = try ZoteroConnection(serverURL: serverURL, apiKey: apiKey)
        let report = try await ZoteroSyncEngine(
            database: database,
            client: ZoteroAPIClient(connection: connection)
        ).pullReadOnly()
        let output = try ReadOnlySyncOutput(
            userID: report.userID,
            previousVersion: report.previousVersion,
            currentVersion: report.currentVersion,
            collections: report.collectionCount,
            items: report.itemCount,
            searches: report.searchCount,
            settings: report.settingCount,
            fullText: report.fullTextCount,
            deletions: report.deletionCount,
            groups: report.groupCount,
            integrity: database.integrityCheck()
        )
        try printJSON(output)
    }

    private func requiredValue(_ flag: String, arguments: [String]) throws -> String {
        guard
            let index = arguments.firstIndex(of: flag),
            arguments.indices.contains(index + 1)
        else {
            throw CLIInputError.missingArgument(flag)
        }
        return arguments[index + 1]
    }

    private func optionalValue(_ flag: String, arguments: [String]) -> String? {
        guard
            let index = arguments.firstIndex(of: flag),
            arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }

    private func zoteroAPIKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard
            let apiKey = environment["SELFHOST_API_KEY"] ?? environment["ZOTERO_API_KEY"],
            !apiKey.isEmpty
        else {
            throw CLIInputError.missingEnvironment("SELFHOST_API_KEY")
        }
        return apiKey
    }

    private func connectionPersistence(
        databasePath: String,
        arguments: [String]
    ) throws -> (CitrationDatabase, FileZoteroCredentialStore) {
        let databaseURL = URL(filePath: databasePath)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let credentialURL = optionalValue("--credential-file", arguments: arguments).map { URL(filePath: $0) }
        return try (
            CitrationDatabase(at: databaseURL),
            FileZoteroCredentialStore(fileURL: credentialURL)
        )
    }

    private func printJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try print(String(data: encoder.encode(value), encoding: .utf8) ?? "{}")
    }
}

// MARK: - ConnectionOutput

private struct ConnectionOutput: Codable {
    let mode: String
    let userID: Int64?
    let canWrite: Bool?
    let canAccessFiles: Bool?
    let integrity: String
}

// MARK: - ReadOnlySyncOutput

private struct ReadOnlySyncOutput: Codable {
    let userID: Int64
    let previousVersion: Int64
    let currentVersion: Int64
    let collections: Int
    let items: Int
    let searches: Int
    let settings: Int
    let fullText: Int
    let deletions: Int
    let groups: Int
    let integrity: String
}

// MARK: - CLIInputError

private enum CLIInputError: Error, CustomStringConvertible {
    case invalidValue(String)
    case missingArgument(String)
    case missingEnvironment(String)

    // MARK: Internal

    var description: String {
        switch self {
        case let .invalidValue(name):
            "Invalid value for \(name)"
        case let .missingArgument(name):
            "Missing required argument \(name)"
        case let .missingEnvironment(name):
            "Missing private environment variable \(name)"
        }
    }
}
