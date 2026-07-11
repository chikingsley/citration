import CitrationCore
import Foundation

extension CitrationCLI {
    func runZoteroAnnotationAcceptance(arguments: [String]) async throws {
        guard arguments.contains("--confirm-disposable") else {
            throw AnnotationAcceptanceError.confirmationRequired
        }
        let server = try annotationRequiredValue("--server", arguments: arguments)
        let databasePath = try annotationRequiredValue("--database", arguments: arguments)
        guard let serverURL = URL(string: server) else {
            throw AnnotationAcceptanceError.invalidServer
        }
        let apiKey = try annotationAPIKey()
        let database = try CitrationDatabase(at: URL(filePath: databasePath))
        let client = try ZoteroAPIClient(connection: ZoteroConnection(serverURL: serverURL, apiKey: apiKey))
        let keyInfo = try await client.keyInfo()
        guard keyInfo.canWriteUserLibrary else {
            throw ZoteroTransportError.keyCannotWriteLibrary
        }
        let keys = AnnotationAcceptanceKeys(
            item: ZoteroObjectKey.random(),
            attachment: ZoteroObjectKey.random(),
            annotation: ZoteroObjectKey.random()
        )
        do {
            let output = try await executeAnnotationAcceptance(
                database: database,
                client: client,
                userID: keyInfo.userID,
                keys: keys
            )
            try annotationPrintJSON(output)
        } catch {
            do {
                try await cleanupAnnotationAcceptance(client: client, userID: keyInfo.userID, keys: keys.all)
            } catch {
                throw AnnotationAcceptanceError.cleanupFailed
            }
            throw error
        }
    }

    private func executeAnnotationAcceptance(
        database: CitrationDatabase,
        client: ZoteroAPIClient,
        userID: Int64,
        keys: AnnotationAcceptanceKeys
    ) async throws -> AnnotationAcceptanceOutput {
        let engine = ZoteroSyncEngine(database: database, client: client)
        _ = try await engine.pullReadOnly()
        let libraryID = try database.upsertLibrary(identity: .init(type: "user", remoteID: userID))

        try database.storeLocalItems([annotationParentItem(key: keys.item)], libraryID: libraryID)
        let itemReport = try await engine.synchronize()
        try requireUpload(itemReport, stage: "parent")
        try database.storeLocalItems(
            [annotationAttachment(key: keys.attachment, parentKey: keys.item)],
            libraryID: libraryID
        )
        let attachmentReport = try await engine.synchronize()
        try requireUpload(attachmentReport, stage: "attachment")
        try database.storeLocalItems(
            [pencilAnnotation(key: keys.annotation, parentKey: keys.attachment)],
            libraryID: libraryID
        )
        let annotationReport = try await engine.synchronize()
        try requireUpload(annotationReport, stage: "annotation")

        let response = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: keys.all,
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard let remoteAnnotation = response.value.first(where: { $0.key == keys.annotation }) else {
            throw AnnotationAcceptanceError.missingRemoteAnnotation
        }
        try verifyPencilAnnotation(remoteAnnotation, parentKey: keys.attachment)
        try await cleanupAnnotationAcceptance(client: client, userID: userID, keys: keys.all)

        return try AnnotationAcceptanceOutput(
            parentCreated: itemReport.uploadedObjectCount == 1,
            attachmentCreated: attachmentReport.uploadedObjectCount == 1,
            annotationCreated: annotationReport.uploadedObjectCount == 1,
            exactInkRoundTrip: true,
            cleanedUp: true,
            integrity: database.integrityCheck()
        )
    }

    private func annotationParentItem(key: String) throws -> ZoteroRawObject {
        try annotationObject(
            key: key,
            itemType: "book",
            fields: [
                "title": .string("Citration disposable iPad annotation acceptance"),
                "creators": .array([]),
                "collections": .array([]),
            ]
        )
    }

    private func annotationAttachment(key: String, parentKey: String) throws -> ZoteroRawObject {
        try annotationObject(
            key: key,
            itemType: "attachment",
            fields: [
                "parentItem": .string(parentKey),
                "linkMode": .string("imported_url"),
                "title": .string("Disposable PDF anchor"),
                "url": .string("https://example.invalid/citration-disposable.pdf"),
                "contentType": .string("application/pdf"),
                "charset": .string("utf-8"),
                "filename": .string("citration-disposable.pdf"),
                "md5": .string("00000000000000000000000000000000"),
                "mtime": .integer(1_700_000_000_000),
                "note": .string(""),
                "accessDate": .string("2026-07-11T18:00:00Z"),
            ]
        )
    }

    private func pencilAnnotation(key: String, parentKey: String) throws -> ZoteroRawObject {
        try annotationObject(
            key: key,
            itemType: "annotation",
            fields: [
                "parentItem": .string(parentKey),
                "annotationType": .string("ink"),
                "annotationColor": .string("#2ea8e5"),
                "annotationPageLabel": .string("1"),
                "annotationSortIndex": .string("00000|000000|00072"),
                "annotationComment": .string("Citration disposable Apple Pencil acceptance"),
                "annotationPosition": .string(Self.pencilPosition),
            ]
        )
    }

    private func annotationObject(
        key: String,
        itemType: String,
        fields: [String: JSONValue]
    ) throws -> ZoteroRawObject {
        let now = ISO8601DateFormatter().string(from: .now)
        var data = fields
        data["key"] = .string(key)
        data["version"] = .integer(0)
        data["itemType"] = .string(itemType)
        data["tags"] = .array([])
        data["relations"] = .object([:])
        data["dateAdded"] = .string(now)
        data["dateModified"] = .string(now)
        return try ZoteroRawObject(rawValue: .object([
            "key": .string(key),
            "version": .integer(0),
            "data": .object(data),
        ]))
    }

    private func verifyPencilAnnotation(_ object: ZoteroRawObject, parentKey: String) throws {
        for (field, expected) in [
            ("itemType", JSONValue.string("annotation")),
            ("parentItem", .string(parentKey)),
            ("annotationType", .string("ink")),
            ("annotationColor", .string("#2ea8e5")),
            ("annotationPosition", .string(Self.pencilPosition)),
        ] where object.data[field] != expected {
            throw AnnotationAcceptanceError.fieldMismatch(field)
        }
    }

    private func requireUpload(_ report: ZoteroSynchronizationReport, stage: String) throws {
        guard report.uploadedObjectCount == 1, report.unresolvedFailureCount == 0 else {
            throw AnnotationAcceptanceError.uploadFailed(
                stage: stage,
                uploaded: report.uploadedObjectCount,
                failures: report.unresolvedFailureCount
            )
        }
    }

    private func cleanupAnnotationAcceptance(
        client: ZoteroAPIClient,
        userID: Int64,
        keys: [String]
    ) async throws {
        let response = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: keys,
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        if !response.value.isEmpty {
            let version = try annotationRequire(response.libraryVersion)
            let existingKeys = response.value.compactMap(\.key)
            _ = try await client.deleteObjects(
                path: "users/\(userID)/items",
                keyParameter: "itemKey",
                keys: existingKeys,
                libraryVersion: version
            )
        }
        let verification = try await client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: keys,
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        guard verification.value.isEmpty else {
            throw AnnotationAcceptanceError.cleanupFailed
        }
    }

    private func annotationRequiredValue(_ flag: String, arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            throw AnnotationAcceptanceError.missingArgument(flag)
        }
        return arguments[index + 1]
    }

    private func annotationAPIKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["SELFHOST_API_KEY"] ?? environment["ZOTERO_API_KEY"], !key.isEmpty else {
            throw AnnotationAcceptanceError.missingAPIKey
        }
        return key
    }

    private func annotationRequire<Value>(_ value: Value?) throws -> Value {
        guard let value else {
            throw AnnotationAcceptanceError.verificationFailed
        }
        return value
    }

    private func annotationPrintJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try print(String(data: encoder.encode(value), encoding: .utf8) ?? "{}")
    }

    private static let pencilPosition = "{\"pageIndex\":0,\"paths\":[[72,180,96,202,130,190]],\"width\":2}"
}

// MARK: - AnnotationAcceptanceKeys

private struct AnnotationAcceptanceKeys {
    let item: String
    let attachment: String
    let annotation: String

    var all: [String] {
        [annotation, attachment, item]
    }
}

// MARK: - AnnotationAcceptanceOutput

private struct AnnotationAcceptanceOutput: Codable {
    let parentCreated: Bool
    let attachmentCreated: Bool
    let annotationCreated: Bool
    let exactInkRoundTrip: Bool
    let cleanedUp: Bool
    let integrity: String
}

// MARK: - AnnotationAcceptanceError

private enum AnnotationAcceptanceError: Error {
    case cleanupFailed
    case confirmationRequired
    case fieldMismatch(String)
    case invalidServer
    case missingAPIKey
    case missingArgument(String)
    case missingRemoteAnnotation
    case uploadFailed(stage: String, uploaded: Int, failures: Int)
    case verificationFailed
}
