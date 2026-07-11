import CitrationCore
import Foundation

extension CitrationCLI {
    func runZoteroStreamingAcceptance(arguments: [String]) async throws {
        guard arguments.contains("--confirm-disposable") else {
            throw StreamingAcceptanceError.confirmationRequired
        }
        let server = try streamingRequiredValue("--server", arguments: arguments)
        let databasePath = try streamingRequiredValue("--database", arguments: arguments)
        guard let serverURL = URL(string: server) else {
            throw StreamingAcceptanceError.invalidServer
        }
        let apiKey = try streamingAPIKey()
        let databaseURL = URL(filePath: databasePath)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let database = try CitrationDatabase(at: databaseURL)
        let connection = try ZoteroConnection(serverURL: serverURL, apiKey: apiKey)
        let client = ZoteroAPIClient(connection: connection)
        let keyInfo = try await client.keyInfo()
        guard keyInfo.canWriteUserLibrary else {
            throw ZoteroTransportError.keyCannotWriteLibrary
        }
        let key = ZoteroObjectKey.random()
        let subscription = ZoteroStreamingSync(
            database: database,
            client: client,
            connection: connection
        ).subscribe()
        defer { subscription.cancel() }
        do {
            let output = try await executeStreamingAcceptance(
                database: database,
                client: client,
                reports: subscription.reports,
                userID: keyInfo.userID,
                key: key
            )
            try streamingPrintJSON(output)
        } catch {
            try await cleanupStreamingAcceptance(client: client, userID: keyInfo.userID, key: key)
            throw error
        }
    }

    private func executeStreamingAcceptance(
        database: CitrationDatabase,
        client: ZoteroAPIClient,
        reports: AsyncThrowingStream<ZoteroPullReport, any Error>,
        userID: Int64,
        key: String
    ) async throws -> StreamingAcceptanceOutput {
        let initial = try await nextStreamingReport(reports)
        let object = try streamingAcceptanceItem(key: key)
        let write = try await client.writeObjects(
            path: "users/\(userID)/items",
            objects: [ZoteroStoredObject(kind: .item, object: object)],
            libraryVersion: initial.currentVersion
        )
        let createdReport = try await nextStreamingReport(reports)
        let libraryID = try database.upsertLibrary(identity: .init(type: "user", remoteID: userID))
        guard
            let created = try database.fetchObject(libraryID: libraryID, kind: .item, key: key),
            !created.isDeleted,
            created.syncState == .synced
        else {
            throw StreamingAcceptanceError.verificationFailed
        }
        let version = write.libraryVersion ?? createdReport.currentVersion
        _ = try await client.deleteObjects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [key],
            libraryVersion: version
        )
        _ = try await nextStreamingReport(reports)
        guard
            let deleted = try database.fetchObject(libraryID: libraryID, kind: .item, key: key),
            deleted.isDeleted,
            try database.fetchProjectedItem(libraryID: libraryID, key: key) == nil
        else {
            throw StreamingAcceptanceError.verificationFailed
        }
        try await verifyStreamingCleanup(client: client, userID: userID, key: key)
        return try StreamingAcceptanceOutput(
            initialAuthoritativePull: true,
            remoteCreatePulled: true,
            remoteDeletePulled: true,
            cleanedUp: true,
            integrity: database.integrityCheck()
        )
    }

    private func nextStreamingReport(
        _ reports: AsyncThrowingStream<ZoteroPullReport, any Error>
    ) async throws -> ZoteroPullReport {
        try await withThrowingTaskGroup(of: ZoteroPullReport.self) { group in
            group.addTask {
                for try await report in reports {
                    return report
                }
                throw StreamingAcceptanceError.streamEnded
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw StreamingAcceptanceError.timeout
            }
            guard let report = try await group.next() else {
                throw StreamingAcceptanceError.streamEnded
            }
            group.cancelAll()
            return report
        }
    }

    private func streamingAcceptanceItem(key: String) throws -> ZoteroRawObject {
        let now = ISO8601DateFormatter().string(from: .now)
        let data = JSONValue.object([
            "key": .string(key),
            "version": .integer(0),
            "itemType": .string("book"),
            "title": .string("Citration disposable streaming acceptance"),
            "creators": .array([]),
            "tags": .array([]),
            "collections": .array([]),
            "relations": .object([:]),
            "dateAdded": .string(now),
            "dateModified": .string(now),
        ])
        return try ZoteroRawObject(rawValue: .object([
            "key": .string(key),
            "version": .integer(0),
            "data": data,
        ]))
    }

    private func cleanupStreamingAcceptance(
        client: ZoteroAPIClient,
        userID: Int64,
        key: String
    ) async throws {
        let existing = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [key],
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard !existing.value.isEmpty else {
            return
        }
        guard let version = existing.libraryVersion else {
            throw StreamingAcceptanceError.verificationFailed
        }
        _ = try await client.deleteObjects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [key],
            libraryVersion: version
        )
        try await verifyStreamingCleanup(client: client, userID: userID, key: key)
    }

    private func verifyStreamingCleanup(client: ZoteroAPIClient, userID: Int64, key: String) async throws {
        let remaining = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [key],
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard remaining.value.isEmpty else {
            throw StreamingAcceptanceError.cleanupFailed
        }
    }

    private func streamingRequiredValue(_ flag: String, arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            throw StreamingAcceptanceError.missingArgument(flag)
        }
        return arguments[index + 1]
    }

    private func streamingAPIKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["SELFHOST_API_KEY"] ?? environment["ZOTERO_API_KEY"], !key.isEmpty else {
            throw StreamingAcceptanceError.missingAPIKey
        }
        return key
    }

    private func streamingPrintJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try print(String(data: encoder.encode(value), encoding: .utf8) ?? "{}")
    }
}

// MARK: - StreamingAcceptanceOutput

private struct StreamingAcceptanceOutput: Encodable {
    let initialAuthoritativePull: Bool
    let remoteCreatePulled: Bool
    let remoteDeletePulled: Bool
    let cleanedUp: Bool
    let integrity: String
}

// MARK: - StreamingAcceptanceError

private enum StreamingAcceptanceError: Error {
    case cleanupFailed
    case confirmationRequired
    case invalidServer
    case missingAPIKey
    case missingArgument(String)
    case streamEnded
    case timeout
    case verificationFailed
}
