@testable import CitrationCore
import Foundation
import GRDB
import Testing

// MARK: - ZoteroSyncTests

@Suite("Zotero synchronization")
struct ZoteroSyncTests {
    // MARK: Internal

    @Test("Connection requires HTTPS outside the local machine and a nonempty key")
    func connectionValidation() throws {
        #expect(throws: ZoteroTransportError.invalidServerURL) {
            try ZoteroConnection(serverURL: #require(URL(string: "http://example.com")), apiKey: "key")
        }
        #expect(throws: ZoteroTransportError.missingAPIKey) {
            try ZoteroConnection(serverURL: #require(URL(string: "https://example.com")), apiKey: "  ")
        }

        let connection = try ZoteroConnection(
            serverURL: #require(URL(string: "http://127.0.0.1:8787")),
            apiKey: " fixture-key\n"
        )
        #expect(connection.serverURL.absoluteString == "http://127.0.0.1:8787/")
        #expect(connection.apiKey == "fixture-key")
        #expect(connection.streamingURL?.absoluteString == "ws://127.0.0.1:8787/stream")

        let official = try ZoteroConnection(
            serverURL: #require(URL(string: "https://api.zotero.org")),
            apiKey: "fixture-key"
        )
        #expect(official.streamingURL?.absoluteString == "wss://stream.zotero.org")
    }

    @Test("Connection profile and scoped credential persist separately in real files")
    func connectionProfileAndCredentialPersistence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "citration-connection-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try CitrationDatabase(at: root.appending(path: "library.sqlite"))
        let credentialURL = root.appending(path: "private/zotero-device-api-key")
        let credentialStore = FileZoteroCredentialStore(fileURL: credentialURL)
        let profile = try ZoteroConnectionProfile(
            serverURL: #require(URL(string: "https://sync.example.test/")),
            userID: 42,
            username: "fixture-user",
            displayName: "Fixture Library",
            canWrite: true,
            canAccessFiles: true
        )

        try database.saveZoteroConnectionProfile(profile)
        try await credentialStore.saveCredential(" fixture-device-key\n")

        #expect(try database.loadZoteroConnectionProfile() == profile)
        #expect(try await credentialStore.loadCredential() == "fixture-device-key")
        let attributes = try FileManager.default.attributesOfItem(atPath: credentialURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
        let columns = try await database.databaseQueue.read { sqlDatabase in
            try Row.fetchAll(sqlDatabase, sql: "PRAGMA table_info(zotero_connection_profile)")
                .map { row -> String in row["name"] }
        }
        #expect(!columns.contains(where: { $0.localizedCaseInsensitiveContains("key") }))
        #expect(!columns.contains(where: { $0.localizedCaseInsensitiveContains("credential") }))

        let manager = ZoteroConnectionManager(database: database, credentialStore: credentialStore)
        #expect(try await manager.configuration() == .connected(profile))
        let activeConnection = try await manager.activeConnection()
        #expect(activeConnection?.serverURL == profile.serverURL)
        #expect(activeConnection?.apiKey == "fixture-device-key")

        try await manager.useLocalOnly()
        #expect(try await manager.configuration() == .localOnly)
        #expect(try await manager.activeConnection() == nil)
        #expect(!FileManager.default.fileExists(atPath: credentialURL.path))
    }

    @Test("Credential store rejects a group-readable device key file")
    func credentialPermissionsAreEnforced() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "citration-credential-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentialURL = root.appending(path: "zotero-device-api-key")
        let store = FileZoteroCredentialStore(fileURL: credentialURL)

        try await store.saveCredential("fixture-device-key")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: credentialURL.path)

        await #expect(throws: ZoteroCredentialStoreError.insecurePermissions) {
            try await store.loadCredential()
        }
    }

    @Test("Deleted response tolerates omitted empty object kinds")
    func deletedResponseDefaultsMissingKinds() throws {
        let deletions = try JSONDecoder().decode(
            ZoteroDeletedObjects.self,
            from: Data(#"{"items":["ITEMKEY"]}"#.utf8)
        )

        #expect(deletions.items == ["ITEMKEY"])
        #expect(deletions.collections.isEmpty)
        #expect(deletions.searches.isEmpty)
        #expect(deletions.settings.isEmpty)
        #expect(deletions.tags.isEmpty)
    }

    @Test("Remote deletions remove synced projections but preserve dirty conflicts")
    func remoteDeletionConflictUsesRealDatabase() throws {
        try withTemporaryDatabase { database in
            let libraryID = try database.upsertLibrary(
                identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
                currentVersion: 1291
            )
            let items = try capturedItems()
            let synced = try #require(items.first)
            let dirty = try #require(items.dropFirst().first)
            let syncedKey = try #require(synced.key)
            let dirtyKey = try #require(dirty.key)
            let unknownDeletedKey = "DELETED1"

            try database.storeRemoteItems([synced], libraryID: libraryID)
            try database.storeLocalItems([dirty], libraryID: libraryID)
            try database.applyRemoteDeletions(
                ZoteroDeletedObjects(items: [syncedKey, dirtyKey, unknownDeletedKey]),
                version: 1300,
                libraryID: libraryID
            )

            let fetchedDeletedObject = try database.fetchObject(
                libraryID: libraryID,
                kind: .item,
                key: syncedKey
            )
            let deletedObject = try #require(fetchedDeletedObject)
            #expect(deletedObject.isDeleted)
            #expect(deletedObject.syncState == .synced)
            #expect(deletedObject.version == 1300)
            #expect(try database.fetchProjectedItem(libraryID: libraryID, key: syncedKey) == nil)

            let fetchedUnknownTombstone = try database.fetchObject(
                libraryID: libraryID,
                kind: .item,
                key: unknownDeletedKey
            )
            let unknownTombstone = try #require(fetchedUnknownTombstone)
            #expect(unknownTombstone.isDeleted)
            #expect(unknownTombstone.version == 1300)
            #expect(unknownTombstone.current == .object(["key": .string(unknownDeletedKey)]))

            let fetchedConflictedObject = try database.fetchObject(
                libraryID: libraryID,
                kind: .item,
                key: dirtyKey
            )
            let conflictedObject = try #require(fetchedConflictedObject)
            #expect(!conflictedObject.isDeleted)
            #expect(conflictedObject.syncState == .failed)
            #expect(try database.fetchProjectedItem(libraryID: libraryID, key: dirtyKey) != nil)
            let failureCount = try database.databaseQueue.read { sqlDatabase in
                try Int.fetchOne(
                    sqlDatabase,
                    sql: """
                    SELECT COUNT(*) FROM synchronization_failures
                    WHERE library_id = ? AND object_kind = 'item' AND object_key = ?
                        AND operation = 'merge-conflict' AND resolved_at IS NULL
                    """,
                    arguments: [libraryID, dirtyKey]
                ) ?? 0
            }
            #expect(failureCount == 1)
            #expect(try database.integrityCheck() == "ok")
        }
    }

    @Test("Local edits preserve the remote version and pristine conflict base")
    func localEditsPreservePristineBase() throws {
        try withTemporaryDatabase { database in
            let libraryID = try database.upsertLibrary(
                identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
                currentVersion: 1291
            )
            let items = try capturedItems()
            let original = try #require(items.first { $0.itemType == "journalArticle" })
            let key = try #require(original.key)
            let originalVersion = try #require(original.version)
            try database.storeRemoteCollections(capturedObjects(filename: "collections.json"), libraryID: libraryID)
            try database.storeRemoteItems([original], libraryID: libraryID)

            let firstEdit = try replacingTitle(in: original, with: "First local title")
            try database.storeLocalItems([firstEdit], libraryID: libraryID)
            let storedFirstEdit = try #require(
                try database.fetchObject(libraryID: libraryID, kind: .item, key: key)
            )
            #expect(storedFirstEdit.version == originalVersion)
            #expect(storedFirstEdit.pristine == original.rawValue)
            #expect(storedFirstEdit.current.objectValue?["data"]?.objectValue?["title"] == .string("First local title"))
            #expect(storedFirstEdit.syncState == .dirty)

            let secondEdit = try replacingTitle(in: firstEdit, with: "Second local title")
            try database.storeLocalItems([secondEdit], libraryID: libraryID)
            let storedSecondEdit = try #require(
                try database.fetchObject(libraryID: libraryID, kind: .item, key: key)
            )
            #expect(storedSecondEdit.version == originalVersion)
            #expect(storedSecondEdit.pristine == original.rawValue)
            #expect(storedSecondEdit.current.objectValue?["data"]?.objectValue?["title"] == .string("Second local title"))
        }
    }

    @Test("Disjoint local and remote fields merge and remain dirty against the new pristine base")
    func disjointRemoteChangesMerge() throws {
        try withTemporaryDatabase { database in
            let (libraryID, original) = try seedRemoteArticle(in: database)
            let key = try #require(original.key)
            try database.storeLocalItems(
                [replacingField("title", with: .string("Local title"), in: original)],
                libraryID: libraryID
            )
            let remote = try replacingField(
                "abstractNote",
                with: .string("Remote abstract"),
                in: original,
                version: 1300
            )

            try database.integrateRemoteItems([remote], libraryID: libraryID)

            let integrated = try #require(
                try database.fetchObject(libraryID: libraryID, kind: .item, key: key)
            )
            #expect(integrated.syncState == .dirty)
            #expect(integrated.version == 1300)
            #expect(integrated.current.objectValue?["data"]?.objectValue?["title"] == .string("Local title"))
            #expect(
                integrated.current.objectValue?["data"]?.objectValue?["abstractNote"]
                    == .string("Remote abstract")
            )
            #expect(integrated.pristine == remote.rawValue)
        }
    }

    @Test("A same-field merge conflict preserves all three versions in the retry record")
    func sameFieldConflictIsPersistent() throws {
        try withTemporaryDatabase { database in
            let (libraryID, original) = try seedRemoteArticle(in: database)
            let key = try #require(original.key)
            try database.storeLocalItems(
                [replacingField("title", with: .string("Local title"), in: original)],
                libraryID: libraryID
            )
            let remote = try replacingField("title", with: .string("Remote title"), in: original, version: 1300)

            try database.integrateRemoteItems([remote], libraryID: libraryID)

            let integrated = try #require(
                try database.fetchObject(libraryID: libraryID, kind: .item, key: key)
            )
            #expect(integrated.syncState == .failed)
            #expect(integrated.pristine == original.rawValue)
            #expect(integrated.current.objectValue?["data"]?.objectValue?["title"] == .string("Local title"))
            let details = try database.databaseQueue.read { sqlDatabase -> JSONValue? in
                let data = try Data.fetchOne(
                    sqlDatabase,
                    sql: """
                    SELECT details_json FROM synchronization_failures
                    WHERE library_id = ? AND object_kind = 'item' AND object_key = ?
                        AND operation = 'merge-conflict' AND resolved_at IS NULL
                    """,
                    arguments: [libraryID, key]
                )
                return try data.map(ZoteroJSON.decode)
            }
            let conflictDetails = try #require(details?.objectValue)
            #expect(conflictDetails["fields"] == .array([.string("title")]))
            #expect(conflictDetails["base"] == original.rawValue)
            #expect(conflictDetails["local"] == integrated.current)
            #expect(conflictDetails["remote"] == remote.rawValue)
        }
    }

    // MARK: Private

    private func capturedItems() throws -> [ZoteroRawObject] {
        try capturedObjects(filename: "items.json")
    }

    private func capturedObjects(filename: String) throws -> [ZoteroRawObject] {
        let fixtureURL = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/Zotero/\(filename)")
        )
        return try JSONDecoder().decode([ZoteroRawObject].self, from: Data(contentsOf: fixtureURL))
    }

    private func replacingTitle(in object: ZoteroRawObject, with title: String) throws -> ZoteroRawObject {
        try replacingField("title", with: .string(title), in: object)
    }

    private func replacingField(
        _ field: String,
        with value: JSONValue,
        in object: ZoteroRawObject,
        version: Int64? = nil
    ) throws -> ZoteroRawObject {
        var envelope = try #require(object.rawValue.objectValue)
        var data = try #require(envelope["data"]?.objectValue)
        data[field] = value
        if let version {
            data["version"] = .integer(version)
            envelope["version"] = .integer(version)
        }
        envelope["data"] = .object(data)
        return try ZoteroRawObject(rawValue: .object(envelope))
    }

    private func seedRemoteArticle(in database: CitrationDatabase) throws -> (Int64, ZoteroRawObject) {
        let libraryID = try database.upsertLibrary(
            identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
            currentVersion: 1291
        )
        let original = try #require(capturedItems().first { $0.itemType == "journalArticle" })
        try database.storeRemoteCollections(capturedObjects(filename: "collections.json"), libraryID: libraryID)
        try database.storeRemoteItems([original], libraryID: libraryID)
        return (libraryID, original)
    }

    private func withTemporaryDatabase(_ body: (CitrationDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-sync-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(CitrationDatabase(at: directory.appending(path: "library.sqlite")))
    }
}
