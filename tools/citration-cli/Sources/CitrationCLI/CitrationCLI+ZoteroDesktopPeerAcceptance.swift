import CitrationCore
import Foundation

extension CitrationCLI {
    func runZoteroDesktopPeerAcceptance(arguments: [String]) async throws {
        let context = try await desktopPeerContext(arguments: arguments)
        var deviceKey: String?
        do {
            let createdDeviceKey = try await createDesktopDeviceKey(
                serverURL: context.connection.serverURL,
                ownerKey: context.ownerKey,
                userID: context.keyInfo.userID
            )
            deviceKey = createdDeviceKey
            try context.harness.prepare(deviceKey: createdDeviceKey)
            let output = try await executeDesktopPeerAcceptance(
                database: context.database,
                client: context.client,
                connection: context.connection,
                harness: context.harness,
                keyInfo: context.keyInfo,
                itemKey: context.itemKey
            )
            try await revokeDesktopDeviceKey(
                serverURL: context.connection.serverURL,
                ownerKey: context.ownerKey,
                userID: context.keyInfo.userID,
                deviceKey: createdDeviceKey
            )
            context.harness.removeAll()
            try desktopPrintJSON(output)
        } catch {
            await cleanupDesktopPeerFailure(context: context, deviceKey: deviceKey)
            throw error
        }
    }

    private func desktopPeerContext(arguments: [String]) async throws -> DesktopPeerContext {
        guard arguments.contains("--confirm-disposable") else {
            throw DesktopPeerAcceptanceError.confirmationRequired
        }
        let server = try desktopRequiredValue("--server", arguments: arguments)
        let databasePath = try desktopRequiredValue("--database", arguments: arguments)
        guard let serverURL = URL(string: server) else {
            throw DesktopPeerAcceptanceError.invalidServer
        }
        let ownerKey = try desktopAPIKey()
        let databaseURL = URL(filePath: databasePath)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let database = try CitrationDatabase(at: databaseURL)
        let connection = try ZoteroConnection(serverURL: serverURL, apiKey: ownerKey)
        guard let streamingURL = connection.streamingURL else {
            throw ZoteroStreamingError.invalidStreamingURL
        }
        let client = ZoteroAPIClient(connection: connection)
        let keyInfo = try await client.keyInfo()
        guard keyInfo.canWriteUserLibrary else {
            throw ZoteroTransportError.keyCannotWriteLibrary
        }
        let root = FileManager.default.temporaryDirectory
            .appending(path: "citration-desktop-peer-\(UUID().uuidString)", directoryHint: .isDirectory)
        let harness = ZoteroDesktopHarness(root: root, serverURL: connection.serverURL, streamingURL: streamingURL)
        try harness.assertZoteroStopped()
        return DesktopPeerContext(
            ownerKey: ownerKey,
            database: database,
            connection: connection,
            client: client,
            keyInfo: keyInfo,
            harness: harness,
            itemKey: ZoteroObjectKey.random()
        )
    }

    private func cleanupDesktopPeerFailure(context: DesktopPeerContext, deviceKey: String?) async {
        try? await cleanupDesktopPeerItem(
            client: context.client,
            userID: context.keyInfo.userID,
            itemKey: context.itemKey
        )
        if let deviceKey {
            try? await revokeDesktopDeviceKey(
                serverURL: context.connection.serverURL,
                ownerKey: context.ownerKey,
                userID: context.keyInfo.userID,
                deviceKey: deviceKey
            )
        }
        context.harness.removeSecret()
    }

    private func executeDesktopPeerAcceptance(
        database: CitrationDatabase,
        client: ZoteroAPIClient,
        connection: ZoteroConnection,
        harness: ZoteroDesktopHarness,
        keyInfo: ZoteroKeyInfo,
        itemKey: String
    ) async throws -> DesktopPeerAcceptanceOutput {
        let subscription = ZoteroStreamingSync(
            database: database,
            client: client,
            connection: connection
        ).subscribe()
        defer { subscription.cancel() }
        let initial = try await nextDesktopReport(subscription.reports)
        let initialTitle = "Citration disposable Desktop peer acceptance"
        let editedTitle = "Citration disposable Desktop peer acceptance edited in Zotero"
        let object = try desktopAcceptanceItem(key: itemKey, title: initialTitle)
        _ = try await client.writeObjects(
            path: "users/\(keyInfo.userID)/items",
            objects: [ZoteroStoredObject(kind: .item, object: object)],
            libraryVersion: initial.currentVersion
        )
        let created = try await nextDesktopReport(subscription.reports)
        let libraryID = try database.upsertLibrary(identity: .init(type: "user", remoteID: keyInfo.userID))
        guard try database.fetchProjectedItem(libraryID: libraryID, key: itemKey)?.title == initialTitle else {
            throw DesktopPeerAcceptanceError.verificationFailed
        }
        try runDesktopEdit(
            harness: harness,
            keyInfo: keyInfo,
            itemKey: itemKey,
            initialTitle: initialTitle,
            editedTitle: editedTitle
        )
        let edited = try await nextDesktopReport(subscription.reports)
        guard try database.fetchProjectedItem(libraryID: libraryID, key: itemKey)?.title == editedTitle else {
            throw DesktopPeerAcceptanceError.verificationFailed
        }
        _ = try await client.deleteObjects(
            path: "users/\(keyInfo.userID)/items",
            keyParameter: "itemKey",
            keys: [itemKey],
            libraryVersion: edited.currentVersion
        )
        _ = try await nextDesktopReport(subscription.reports)
        try runDesktopDeletion(harness: harness, keyInfo: keyInfo, itemKey: itemKey)
        try await verifyDesktopPeerCleanup(client: client, userID: keyInfo.userID, itemKey: itemKey)
        return try DesktopPeerAcceptanceOutput(
            citrationCreateSeenInDesktop: created.currentVersion > initial.currentVersion,
            desktopEditReturnedToCitration: true,
            citrationDeleteSeenInDesktop: true,
            deviceKeyRevoked: true,
            cleanedUp: true,
            integrity: database.integrityCheck()
        )
    }

    private func runDesktopEdit(
        harness: ZoteroDesktopHarness,
        keyInfo: ZoteroKeyInfo,
        itemKey: String,
        initialTitle: String,
        editedTitle: String
    ) throws {
        let result = try harness.run(
            body: desktopEditScript(
                keyFile: harness.keyFile,
                userID: keyInfo.userID,
                username: keyInfo.username,
                itemKey: itemKey,
                initialTitle: initialTitle,
                editedTitle: editedTitle
            ),
            as: DesktopEditResult.self
        )
        guard result.itemKey == itemKey, result.title == editedTitle else {
            throw DesktopPeerAcceptanceError.verificationFailed
        }
    }

    private func runDesktopDeletion(
        harness: ZoteroDesktopHarness,
        keyInfo: ZoteroKeyInfo,
        itemKey: String
    ) throws {
        let result = try harness.run(
            body: desktopDeletionScript(
                keyFile: harness.keyFile,
                userID: keyInfo.userID,
                username: keyInfo.username,
                itemKey: itemKey
            ),
            as: DesktopDeletionResult.self
        )
        guard result.absent else {
            throw DesktopPeerAcceptanceError.verificationFailed
        }
    }

    private func desktopEditScript(
        keyFile: URL,
        userID: Int64,
        username: String,
        itemKey: String,
        initialTitle: String,
        editedTitle: String
    ) -> String {
        """
            await configure(\(desktopJSONString(keyFile.path)), \(userID), \(desktopJSONString(username)));
            await syncUserLibrary(true);
            const book = await Zotero.Items.getByLibraryAndKeyAsync(
              Zotero.Libraries.userLibraryID,
              \(desktopJSONString(itemKey))
            );
            if (!book) throw new Error("Desktop did not download the Citration item");
            if (book.getField("title") !== \(desktopJSONString(initialTitle))) {
              throw new Error("Desktop received the wrong Citration title");
            }
            book.setField("title", \(desktopJSONString(editedTitle)));
            await book.saveTx();
            await syncUserLibrary(false);
            return { itemKey: book.key, title: book.getField("title") };
        \(desktopScriptHelpers)
        """
    }

    private func desktopDeletionScript(
        keyFile: URL,
        userID: Int64,
        username: String,
        itemKey: String
    ) -> String {
        """
            await configure(\(desktopJSONString(keyFile.path)), \(userID), \(desktopJSONString(username)));
            await syncUserLibrary(true);
            const book = await Zotero.Items.getByLibraryAndKeyAsync(
              Zotero.Libraries.userLibraryID,
              \(desktopJSONString(itemKey))
            );
            return { absent: !book || book.deleted === true };
        \(desktopScriptHelpers)
        """
    }

    private var desktopScriptHelpers: String {
        """
            async function configure(path, id, name) {
              const key = (await Zotero.File.getContentsAsync(path)).trim();
              await Zotero.Users.setCurrentUserID(id);
              await Zotero.Users.setCurrentUsername(name);
              await Zotero.Users.setCurrentName(name);
              await Zotero.Sync.Data.Local.setAPIKey(key);
            }
            async function syncUserLibrary(firstInSession) {
              const libraryID = Zotero.Libraries.userLibraryID;
              await Zotero.Sync.Runner.sync({
                background: false,
                fileLibraries: [],
                firstInSession,
                fullTextLibraries: [],
                libraries: [libraryID],
                stopOnError: true,
                onError: (error) => { throw error; }
              });
            }
        """
    }

    private func nextDesktopReport(
        _ reports: AsyncThrowingStream<ZoteroPullReport, any Error>
    ) async throws -> ZoteroPullReport {
        try await withThrowingTaskGroup(of: ZoteroPullReport.self) { group in
            group.addTask {
                for try await report in reports {
                    return report
                }
                throw DesktopPeerAcceptanceError.streamEnded
            }
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw DesktopPeerAcceptanceError.timeout
            }
            guard let report = try await group.next() else {
                throw DesktopPeerAcceptanceError.streamEnded
            }
            group.cancelAll()
            return report
        }
    }

    private func desktopAcceptanceItem(key: String, title: String) throws -> ZoteroRawObject {
        let now = ISO8601DateFormatter().string(from: .now)
        let data = JSONValue.object([
            "key": .string(key), "version": .integer(0), "itemType": .string("book"),
            "title": .string(title), "creators": .array([]), "tags": .array([]),
            "collections": .array([]), "relations": .object([:]),
            "dateAdded": .string(now), "dateModified": .string(now),
        ])
        return try ZoteroRawObject(rawValue: .object([
            "key": .string(key), "version": .integer(0), "data": data,
        ]))
    }

    private func createDesktopDeviceKey(
        serverURL: URL,
        ownerKey: String,
        userID: Int64
    ) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "access": [
                "groups": [:],
                "user": ["files": true, "library": true, "notes": true, "write": true],
            ],
            "name": "Citration Desktop peer acceptance",
        ])
        let response = try await desktopKeyRequest(
            serverURL: serverURL,
            ownerKey: ownerKey,
            path: "users/\(userID)/keys",
            method: "POST",
            body: body
        )
        guard response.status == 201 else {
            throw DesktopPeerAcceptanceError.deviceKeyRequestFailed(response.status)
        }
        let key = try JSONDecoder().decode(DesktopDeviceKey.self, from: response.data).key
        guard !key.isEmpty else {
            throw DesktopPeerAcceptanceError.deviceKeyRequestFailed(response.status)
        }
        return key
    }

    private func revokeDesktopDeviceKey(
        serverURL: URL,
        ownerKey: String,
        userID: Int64,
        deviceKey: String
    ) async throws {
        let response = try await desktopKeyRequest(
            serverURL: serverURL,
            ownerKey: ownerKey,
            path: "users/\(userID)/keys/\(deviceKey)",
            method: "DELETE",
            body: nil
        )
        guard response.status == 204 || response.status == 404 else {
            throw DesktopPeerAcceptanceError.deviceKeyRequestFailed(response.status)
        }
    }

    private func desktopKeyRequest(
        serverURL: URL,
        ownerKey: String,
        path: String,
        method: String,
        body: Data?
    ) async throws -> DesktopKeyResponse {
        var request = URLRequest(url: serverURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(ownerKey, forHTTPHeaderField: "Zotero-API-Key")
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DesktopPeerAcceptanceError.verificationFailed
        }
        return DesktopKeyResponse(status: http.statusCode, data: data)
    }

    private func cleanupDesktopPeerItem(client: ZoteroAPIClient, userID: Int64, itemKey: String) async throws {
        let existing = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [itemKey],
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard !existing.value.isEmpty else {
            return
        }
        guard let version = existing.libraryVersion else {
            throw DesktopPeerAcceptanceError.verificationFailed
        }
        _ = try await client.deleteObjects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [itemKey],
            libraryVersion: version
        )
    }

    private func verifyDesktopPeerCleanup(client: ZoteroAPIClient, userID: Int64, itemKey: String) async throws {
        let remaining = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: [itemKey],
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard remaining.value.isEmpty else {
            throw DesktopPeerAcceptanceError.cleanupFailed
        }
    }

    private func desktopJSONString(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try? encoder.encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private func desktopRequiredValue(_ flag: String, arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            throw DesktopPeerAcceptanceError.missingArgument(flag)
        }
        return arguments[index + 1]
    }

    private func desktopAPIKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["SELFHOST_API_KEY"] ?? environment["ZOTERO_API_KEY"], !key.isEmpty else {
            throw DesktopPeerAcceptanceError.missingAPIKey
        }
        return key
    }

    private func desktopPrintJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try print(String(data: encoder.encode(value), encoding: .utf8) ?? "{}")
    }
}

// MARK: - DesktopDeviceKey

private struct DesktopDeviceKey: Decodable {
    let key: String
}

// MARK: - DesktopPeerContext

private struct DesktopPeerContext {
    let ownerKey: String
    let database: CitrationDatabase
    let connection: ZoteroConnection
    let client: ZoteroAPIClient
    let keyInfo: ZoteroKeyInfo
    let harness: ZoteroDesktopHarness
    let itemKey: String
}

// MARK: - DesktopKeyResponse

private struct DesktopKeyResponse {
    let status: Int
    let data: Data
}

// MARK: - DesktopEditResult

private struct DesktopEditResult: Decodable {
    let itemKey: String
    let title: String
}

// MARK: - DesktopDeletionResult

private struct DesktopDeletionResult: Decodable {
    let absent: Bool
}

// MARK: - DesktopPeerAcceptanceOutput

private struct DesktopPeerAcceptanceOutput: Encodable {
    let citrationCreateSeenInDesktop: Bool
    let desktopEditReturnedToCitration: Bool
    let citrationDeleteSeenInDesktop: Bool
    let deviceKeyRevoked: Bool
    let cleanedUp: Bool
    let integrity: String
}

// MARK: - DesktopPeerAcceptanceError

private enum DesktopPeerAcceptanceError: Error {
    case cleanupFailed
    case confirmationRequired
    case deviceKeyRequestFailed(Int)
    case invalidServer
    case missingAPIKey
    case missingArgument(String)
    case streamEnded
    case timeout
    case verificationFailed
}
