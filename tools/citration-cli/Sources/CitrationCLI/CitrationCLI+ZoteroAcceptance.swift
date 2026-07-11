import CitrationCore
import Foundation

extension CitrationCLI {
    func runZoteroDisposableAcceptance(arguments: [String]) async throws {
        guard arguments.contains("--confirm-disposable") else {
            throw ZoteroAcceptanceError.confirmationRequired
        }
        let server = try acceptanceRequiredValue("--server", arguments: arguments)
        let databasePath = try acceptanceRequiredValue("--database", arguments: arguments)
        guard let serverURL = URL(string: server) else {
            throw ZoteroAcceptanceError.invalidServer
        }
        let apiKey = try acceptanceAPIKey()
        let database = try CitrationDatabase(at: URL(filePath: databasePath))
        let client = try ZoteroAPIClient(connection: ZoteroConnection(serverURL: serverURL, apiKey: apiKey))
        let keyInfo = try await client.keyInfo()
        guard keyInfo.canWriteUserLibrary else {
            throw ZoteroTransportError.keyCannotWriteLibrary
        }
        let key = ZoteroObjectKey.random()
        do {
            let output = try await executeAcceptance(
                database: database,
                client: client,
                userID: keyInfo.userID,
                key: key
            )
            try acceptancePrintJSON(output)
        } catch {
            do {
                try await cleanupDisposable(client: client, userID: keyInfo.userID, key: key)
            } catch {
                throw ZoteroAcceptanceError.cleanupFailed(key: key)
            }
            throw error
        }
    }

    private func executeAcceptance(
        database: CitrationDatabase,
        client: ZoteroAPIClient,
        userID: Int64,
        key: String
    ) async throws -> ZoteroAcceptanceOutput {
        let engine = ZoteroSyncEngine(database: database, client: client)
        _ = try await engine.pullReadOnly()
        let libraryID = try database.upsertLibrary(
            identity: ZoteroLibraryIdentity(type: "user", remoteID: userID)
        )
        let created = try disposableItem(key: key)
        try database.storeLocalItems([created], libraryID: libraryID)
        let createReport = try await engine.synchronize()
        let remoteCreated = try await requireRemoteItem(client: client, userID: userID, key: key)

        try database.storeLocalItems(
            [replacingField("title", value: .string("Citration disposable local edit"), in: remoteCreated.object)],
            libraryID: libraryID
        )
        _ = try await writeRemoteField(
            client: client,
            userID: userID,
            remote: remoteCreated,
            field: "abstractNote",
            value: .string("Citration disposable remote edit")
        )
        let mergeReport = try await engine.synchronize()
        let merged = try await requireRemoteItem(client: client, userID: userID, key: key)
        try verifyMerged(merged.object)
        let conflictReport = try await createAndVerifyConflict(
            database: database,
            client: client,
            engine: engine,
            libraryID: libraryID,
            userID: userID,
            remote: merged
        )
        try database.resolveConflict(kind: .item, key: key, resolution: .keepRemote, libraryID: libraryID)
        try database.markLocalDeletion(kind: .item, key: key, libraryID: libraryID)
        let deletionReport = try await engine.synchronize()
        try await cleanupDisposable(client: client, userID: userID, key: key)
        return try ZoteroAcceptanceOutput(
            disposableKey: key,
            created: createReport.uploadedObjectCount == 1,
            disjointMergeRoundTripped: mergeReport.uploadedObjectCount == 1,
            conflictPreserved: conflictReport.unresolvedFailureCount == 1,
            deletedThroughSync: deletionReport.deletedObjectCount == 1,
            cleanedUp: true,
            integrity: database.integrityCheck()
        )
    }

    private func createAndVerifyConflict(
        database: CitrationDatabase,
        client: ZoteroAPIClient,
        engine: ZoteroSyncEngine,
        libraryID: Int64,
        userID: Int64,
        remote: RemoteAcceptanceItem
    ) async throws -> ZoteroSynchronizationReport {
        let key = try requiredKey(remote.object)
        try database.storeLocalItems(
            [replacingField("title", value: .string("Citration disposable local conflict"), in: remote.object)],
            libraryID: libraryID
        )
        _ = try await writeRemoteField(
            client: client,
            userID: userID,
            remote: remote,
            field: "title",
            value: .string("Citration disposable remote conflict")
        )
        let report = try await engine.synchronize()
        let server = try await requireRemoteItem(client: client, userID: userID, key: key)
        guard
            server.object.data["title"] == .string("Citration disposable remote conflict"),
            let local = try database.fetchObject(libraryID: libraryID, kind: .item, key: key),
            local.syncState == .failed,
            local.current.objectValue?["data"]?.objectValue?["title"]
            == .string("Citration disposable local conflict")
        else {
            throw ZoteroAcceptanceError.verificationFailed
        }
        return report
    }

    private func writeRemoteField(
        client: ZoteroAPIClient,
        userID: Int64,
        remote: RemoteAcceptanceItem,
        field: String,
        value: JSONValue
    ) async throws -> ZoteroResponse<ZoteroWriteReport> {
        let changed = try replacingField(field, value: value, in: remote.object)
        return try await client.writeObjects(
            path: "users/\(userID)/items",
            objects: [ZoteroStoredObject(kind: .item, object: changed)],
            libraryVersion: remote.libraryVersion
        )
    }

    private func cleanupDisposable(client: ZoteroAPIClient, userID: Int64, key: String) async throws {
        let response = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [key],
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard !response.value.isEmpty else {
            return
        }
        guard let version = response.libraryVersion else {
            throw ZoteroTransportError.missingHeader("Last-Modified-Version")
        }
        _ = try await client.deleteObjects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [key],
            libraryVersion: version
        )
        let verification = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [key],
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard verification.value.isEmpty else {
            throw ZoteroAcceptanceError.cleanupFailed(key: key)
        }
    }

    private func requireRemoteItem(
        client: ZoteroAPIClient,
        userID: Int64,
        key: String
    ) async throws -> RemoteAcceptanceItem {
        let response = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [key],
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard let object = response.value.first, let version = response.libraryVersion else {
            throw ZoteroAcceptanceError.verificationFailed
        }
        return RemoteAcceptanceItem(object: object, libraryVersion: version)
    }

    private func disposableItem(key: String) throws -> ZoteroRawObject {
        let now = ISO8601DateFormatter().string(from: .now)
        let data = JSONValue.object([
            "key": .string(key),
            "version": .integer(0),
            "itemType": .string("book"),
            "title": .string("Citration disposable sync acceptance"),
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

    private func replacingField(
        _ field: String,
        value: JSONValue,
        in object: ZoteroRawObject
    ) throws -> ZoteroRawObject {
        var envelope = try acceptanceRequire(object.rawValue.objectValue)
        var data = try acceptanceRequire(envelope["data"]?.objectValue)
        data[field] = value
        envelope["data"] = .object(data)
        return try ZoteroRawObject(rawValue: .object(envelope))
    }

    private func verifyMerged(_ object: ZoteroRawObject) throws {
        guard
            object.data["title"] == .string("Citration disposable local edit"),
            object.data["abstractNote"] == .string("Citration disposable remote edit")
        else {
            throw ZoteroAcceptanceError.verificationFailed
        }
    }

    private func requiredKey(_ object: ZoteroRawObject) throws -> String {
        try acceptanceRequire(object.key)
    }

    private func acceptanceRequiredValue(_ flag: String, arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            throw ZoteroAcceptanceError.missingArgument(flag)
        }
        return arguments[index + 1]
    }

    private func acceptanceAPIKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["SELFHOST_API_KEY"] ?? environment["ZOTERO_API_KEY"], !key.isEmpty else {
            throw ZoteroAcceptanceError.missingAPIKey
        }
        return key
    }

    private func acceptanceRequire<Value>(_ value: Value?) throws -> Value {
        guard let value else {
            throw ZoteroAcceptanceError.verificationFailed
        }
        return value
    }

    private func acceptancePrintJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try print(String(data: encoder.encode(value), encoding: .utf8) ?? "{}")
    }
}

// MARK: - RemoteAcceptanceItem

private struct RemoteAcceptanceItem {
    let object: ZoteroRawObject
    let libraryVersion: Int64
}

// MARK: - ZoteroAcceptanceOutput

private struct ZoteroAcceptanceOutput: Codable {
    let disposableKey: String
    let created: Bool
    let disjointMergeRoundTripped: Bool
    let conflictPreserved: Bool
    let deletedThroughSync: Bool
    let cleanedUp: Bool
    let integrity: String
}

// MARK: - ZoteroAcceptanceError

private enum ZoteroAcceptanceError: Error {
    case cleanupFailed(key: String)
    case confirmationRequired
    case invalidServer
    case missingAPIKey
    case missingArgument(String)
    case verificationFailed
}
