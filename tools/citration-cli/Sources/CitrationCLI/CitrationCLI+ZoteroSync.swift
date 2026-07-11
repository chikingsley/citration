import CitrationCore
import Foundation

extension CitrationCLI {
    func syncZoteroReadOnly(arguments: [String]) async throws {
        let server = try requiredValue("--server", arguments: arguments)
        let databasePath = try requiredValue("--database", arguments: arguments)
        guard let serverURL = URL(string: server) else {
            throw CLIInputError.invalidValue("--server")
        }
        let environment = ProcessInfo.processInfo.environment
        guard
            let apiKey = environment["SELFHOST_API_KEY"] ?? environment["ZOTERO_API_KEY"],
            !apiKey.isEmpty
        else {
            throw CLIInputError.missingEnvironment("SELFHOST_API_KEY")
        }

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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try print(String(data: encoder.encode(output), encoding: .utf8) ?? "{}")
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
