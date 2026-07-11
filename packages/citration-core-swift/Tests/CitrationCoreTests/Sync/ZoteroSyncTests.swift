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
            #expect(conflictedObject.syncState == .dirty)
            #expect(try database.fetchProjectedItem(libraryID: libraryID, key: dirtyKey) != nil)
            let failureCount = try database.databaseQueue.read { sqlDatabase in
                try Int.fetchOne(
                    sqlDatabase,
                    sql: """
                    SELECT COUNT(*) FROM synchronization_failures
                    WHERE library_id = ? AND object_kind = 'item' AND object_key = ?
                        AND operation = 'remote-delete' AND resolved_at IS NULL
                    """,
                    arguments: [libraryID, dirtyKey]
                ) ?? 0
            }
            #expect(failureCount == 1)
            #expect(try database.integrityCheck() == "ok")
        }
    }

    // MARK: Private

    private func capturedItems() throws -> [ZoteroRawObject] {
        let fixtureURL = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/Zotero/items.json")
        )
        return try JSONDecoder().decode([ZoteroRawObject].self, from: Data(contentsOf: fixtureURL))
    }

    private func withTemporaryDatabase(_ body: (CitrationDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-sync-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(CitrationDatabase(at: directory.appending(path: "library.sqlite")))
    }
}
