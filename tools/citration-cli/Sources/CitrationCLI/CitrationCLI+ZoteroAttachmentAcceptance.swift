import CitrationCore
import Foundation

extension CitrationCLI {
    func runZoteroAttachmentAcceptance(arguments: [String]) async throws {
        guard arguments.contains("--confirm-disposable") else {
            throw AttachmentAcceptanceError.confirmationRequired
        }
        let server = try attachmentRequiredValue("--server", arguments: arguments)
        let databasePath = try attachmentRequiredValue("--database", arguments: arguments)
        guard let serverURL = URL(string: server) else {
            throw AttachmentAcceptanceError.invalidServer
        }
        let apiKey = try attachmentAPIKey()
        let root = URL(filePath: databasePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try CitrationDatabase(at: URL(filePath: databasePath))
        let client = try ZoteroAPIClient(connection: ZoteroConnection(serverURL: serverURL, apiKey: apiKey))
        let keyInfo = try await client.keyInfo()
        guard keyInfo.canWriteUserLibrary else {
            throw ZoteroTransportError.keyCannotWriteLibrary
        }
        guard keyInfo.canAccessUserFiles else {
            throw ZoteroTransportError.keyCannotAccessFiles
        }
        let keys = AttachmentAcceptanceKeys(
            parent: ZoteroObjectKey.random(),
            small: ZoteroObjectKey.random(),
            multipart: ZoteroObjectKey.random(),
            standard: ZoteroObjectKey.random()
        )
        do {
            let output = try await executeAttachmentAcceptance(
                root: root,
                database: database,
                client: client,
                userID: keyInfo.userID,
                keys: keys
            )
            try attachmentPrintJSON(output)
        } catch {
            do {
                try await cleanupAttachmentAcceptance(client: client, userID: keyInfo.userID, keys: keys.all)
            } catch {
                throw AttachmentAcceptanceError.cleanupFailed
            }
            throw error
        }
    }

    private func executeAttachmentAcceptance(
        root: URL,
        database: CitrationDatabase,
        client: ZoteroAPIClient,
        userID: Int64,
        keys: AttachmentAcceptanceKeys
    ) async throws -> AttachmentAcceptanceOutput {
        let engine = ZoteroSyncEngine(database: database, client: client)
        _ = try await engine.pullReadOnly()
        let libraryID = try database.upsertLibrary(identity: .init(type: "user", remoteID: userID))
        let prepared = try prepareAttachmentFixtures(root: root, database: database, libraryID: libraryID, keys: keys)
        _ = try await engine.synchronize()
        let transfer = try ZoteroAttachmentTransfer(
            database: database,
            client: client,
            attachmentsDirectory: prepared.directory
        )
        let upload = try await transfer.uploadPending()
        guard
            upload.failedCount == 0,
            upload.directSingleCount == 1,
            upload.directMultipartCount == 1
        else {
            throw AttachmentAcceptanceError.verificationFailed
        }
        _ = try await engine.pullReadOnly()
        let standard = try prepareStandardFixture(database: database, libraryID: libraryID, prepared: prepared, keys: keys)
        _ = try await engine.synchronize()
        let standardTransfer = try ZoteroAttachmentTransfer(
            database: database,
            client: client,
            attachmentsDirectory: prepared.directory,
            prefersDirectUploads: false
        )
        let standardUpload = try await standardTransfer.uploadPending()
        guard standardUpload.failedCount == 0, standardUpload.standardUploadCount == 1 else {
            throw AttachmentAcceptanceError.verificationFailed
        }
        _ = try await engine.pullReadOnly()
        try await verifyAttachmentDownloads(transfer: transfer, prepared: prepared, standard: standard, keys: keys)
        for key in keys.all {
            try database.markLocalDeletion(kind: .item, key: key, libraryID: libraryID)
        }
        _ = try await engine.synchronize()
        try await verifyAttachmentCleanup(client: client, userID: userID, keys: keys.all)
        return try AttachmentAcceptanceOutput(
            smallDirectUpload: true,
            multipartDirectUpload: true,
            standardUpload: true,
            verifiedDownloads: 3,
            cleanedUp: true,
            integrity: database.integrityCheck()
        )
    }

    private func prepareStandardFixture(
        database: CitrationDatabase,
        libraryID: Int64,
        prepared: PreparedAttachmentFixtures,
        keys: AttachmentAcceptanceKeys
    ) throws -> PreparedStandardAttachment {
        let url = prepared.directory.appending(path: "standard-acceptance.txt")
        let data = Data("Citration standard upload acceptance\n".utf8)
        try data.write(to: url)
        try database.storeLocalItems(
            [attachmentAcceptanceItem(
                key: keys.standard,
                parentKey: keys.parent,
                filename: url.lastPathComponent,
                contentType: "text/plain"
            )],
            libraryID: libraryID
        )
        try database.markAttachmentTransferComplete(
            libraryID: libraryID,
            itemKey: keys.standard,
            localURL: url,
            md5: "",
            sha256: "",
            remoteMTime: nil
        )
        return PreparedStandardAttachment(url: url, size: data.count)
    }

    private func prepareAttachmentFixtures(
        root: URL,
        database: CitrationDatabase,
        libraryID: Int64,
        keys: AttachmentAcceptanceKeys
    ) throws -> PreparedAttachmentFixtures {
        let directory = root.appending(path: "attachments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let smallURL = directory.appending(path: "small-acceptance.txt")
        let multipartURL = directory.appending(path: "multipart-acceptance.bin")
        let smallData = Data("Citration attachment acceptance\n".utf8)
        try smallData.write(to: smallURL)
        try createSparseFile(at: multipartURL, size: 65 * 1024 * 1024)
        try database.storeLocalItems(
            [
                attachmentAcceptanceParent(key: keys.parent),
                attachmentAcceptanceItem(
                    key: keys.small,
                    parentKey: keys.parent,
                    filename: smallURL.lastPathComponent,
                    contentType: "text/plain"
                ),
                attachmentAcceptanceItem(
                    key: keys.multipart,
                    parentKey: keys.parent,
                    filename: multipartURL.lastPathComponent,
                    contentType: "application/octet-stream"
                ),
            ],
            libraryID: libraryID
        )
        for (key, url) in [(keys.small, smallURL), (keys.multipart, multipartURL)] {
            try database.markAttachmentTransferComplete(
                libraryID: libraryID,
                itemKey: key,
                localURL: url,
                md5: "",
                sha256: "",
                remoteMTime: nil
            )
        }
        return PreparedAttachmentFixtures(
            directory: directory,
            smallURL: smallURL,
            multipartURL: multipartURL,
            smallSize: smallData.count
        )
    }

    private func verifyAttachmentDownloads(
        transfer: ZoteroAttachmentTransfer,
        prepared: PreparedAttachmentFixtures,
        standard: PreparedStandardAttachment,
        keys: AttachmentAcceptanceKeys
    ) async throws {
        try FileManager.default.removeItem(at: prepared.smallURL)
        try FileManager.default.removeItem(at: prepared.multipartURL)
        try FileManager.default.removeItem(at: standard.url)
        let downloadedSmall = try await transfer.download(itemKey: keys.small)
        let downloadedMultipart = try await transfer.download(itemKey: keys.multipart)
        let downloadedStandard = try await transfer.download(itemKey: keys.standard)
        guard
            try fileSize(downloadedSmall) == prepared.smallSize,
            try fileSize(downloadedMultipart) == 65 * 1024 * 1024,
            try fileSize(downloadedStandard) == standard.size
        else {
            throw AttachmentAcceptanceError.verificationFailed
        }
    }

    private func attachmentAcceptanceParent(key: String) throws -> ZoteroRawObject {
        try attachmentAcceptanceObject(key: key, data: [
            "itemType": .string("book"),
            "title": .string("Citration disposable attachment acceptance"),
            "creators": .array([]),
            "tags": .array([]),
            "collections": .array([]),
            "relations": .object([:]),
        ])
    }

    private func attachmentAcceptanceItem(
        key: String,
        parentKey: String,
        filename: String,
        contentType: String
    ) throws -> ZoteroRawObject {
        try attachmentAcceptanceObject(key: key, data: [
            "itemType": .string("attachment"),
            "parentItem": .string(parentKey),
            "linkMode": .string("imported_file"),
            "title": .string(filename),
            "filename": .string(filename),
            "contentType": .string(contentType),
            "charset": .string(""),
            "tags": .array([]),
            "collections": .array([]),
            "relations": .object([:]),
        ])
    }

    private func attachmentAcceptanceObject(
        key: String,
        data rawData: [String: JSONValue]
    ) throws -> ZoteroRawObject {
        var data = rawData
        data["key"] = .string(key)
        data["version"] = .integer(0)
        let now = ISO8601DateFormatter().string(from: .now)
        data["dateAdded"] = .string(now)
        data["dateModified"] = .string(now)
        return try ZoteroRawObject(rawValue: .object([
            "key": .string(key),
            "version": .integer(0),
            "data": .object(data),
        ]))
    }

    private func cleanupAttachmentAcceptance(
        client: ZoteroAPIClient,
        userID: Int64,
        keys: [String]
    ) async throws {
        let existing = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: keys,
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard !existing.value.isEmpty else {
            return
        }
        guard let version = existing.libraryVersion else {
            throw AttachmentAcceptanceError.verificationFailed
        }
        _ = try await client.deleteObjects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: existing.value.compactMap(\.key),
            libraryVersion: version
        )
        try await verifyAttachmentCleanup(client: client, userID: userID, keys: keys)
    }

    private func verifyAttachmentCleanup(
        client: ZoteroAPIClient,
        userID: Int64,
        keys: [String]
    ) async throws {
        let remaining = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: keys,
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard remaining.value.isEmpty else {
            throw AttachmentAcceptanceError.cleanupFailed
        }
    }

    private func createSparseFile(at url: URL, size: Int64) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(size))
    }

    private func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw AttachmentAcceptanceError.verificationFailed
        }
        return size
    }

    private func attachmentRequiredValue(_ flag: String, arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            throw AttachmentAcceptanceError.missingArgument(flag)
        }
        return arguments[index + 1]
    }

    private func attachmentAPIKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["SELFHOST_API_KEY"] ?? environment["ZOTERO_API_KEY"], !key.isEmpty else {
            throw AttachmentAcceptanceError.missingAPIKey
        }
        return key
    }

    private func attachmentPrintJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try print(String(data: encoder.encode(value), encoding: .utf8) ?? "{}")
    }
}

// MARK: - AttachmentAcceptanceKeys

private struct AttachmentAcceptanceKeys {
    let parent: String
    let small: String
    let multipart: String
    let standard: String

    var all: [String] {
        [small, multipart, standard, parent]
    }
}

// MARK: - PreparedAttachmentFixtures

private struct PreparedAttachmentFixtures {
    let directory: URL
    let smallURL: URL
    let multipartURL: URL
    let smallSize: Int
}

// MARK: - PreparedStandardAttachment

private struct PreparedStandardAttachment {
    let url: URL
    let size: Int
}

// MARK: - AttachmentAcceptanceOutput

private struct AttachmentAcceptanceOutput: Encodable {
    let smallDirectUpload: Bool
    let multipartDirectUpload: Bool
    let standardUpload: Bool
    let verifiedDownloads: Int
    let cleanedUp: Bool
    let integrity: String
}

// MARK: - AttachmentAcceptanceError

private enum AttachmentAcceptanceError: Error {
    case cleanupFailed
    case confirmationRequired
    case invalidServer
    case missingAPIKey
    case missingArgument(String)
    case verificationFailed
}
