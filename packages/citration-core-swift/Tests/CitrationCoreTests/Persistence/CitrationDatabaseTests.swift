@testable import CitrationCore
import Foundation
import Testing

@Suite("CitrationDatabase")
struct CitrationDatabaseTests {
    // MARK: Internal

    @Test("Every captured response survives a real SQLite round trip")
    func capturedResponsesRoundTrip() throws {
        try withTemporaryDatabase { database in
            let libraryID = try database.upsertLibrary(
                identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
                name: "Fixture Library",
                currentVersion: 1291
            )

            let fixtureURLs = try FileManager.default.contentsOfDirectory(
                at: fixtureDirectory(),
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" && $0.lastPathComponent != "manifest.json" }

            for fixtureURL in fixtureURLs {
                let original = try ZoteroJSON.decode(Data(contentsOf: fixtureURL))
                let key = fixtureURL.deletingPathExtension().lastPathComponent
                try database.storeRemoteObjects(
                    [ZoteroStoredObject(
                        kind: ZoteroObjectKind(rawValue: "fixture"),
                        key: key,
                        version: 1291,
                        current: original
                    )],
                    libraryID: libraryID
                )

                let fetched = try database.fetchObject(
                    libraryID: libraryID,
                    kind: ZoteroObjectKind(rawValue: "fixture"),
                    key: key
                )
                let reloaded = try #require(fetched)
                #expect(reloaded.current == original)
                #expect(reloaded.pristine == original)
                #expect(try ZoteroJSON.decode(ZoteroJSON.encode(reloaded.current)) == original)
            }

            #expect(try database.objectCount(libraryID: libraryID) == fixtureURLs.count)
            #expect(try database.integrityCheck() == "ok")
            #expect(try database.schemaObjects().isSuperset(of: Self.requiredSchemaObjects))
        }
    }

    @Test("Captured Zotero objects retain identity, type, version, and pristine JSON")
    func capturedObjectsRoundTrip() throws {
        try withTemporaryDatabase { database in
            let libraryID = try database.upsertLibrary(
                identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
                currentVersion: 1291
            )
            let fixtureData = try Data(contentsOf: fixtureDirectory().appending(path: "items.json"))
            let rawObjects = try JSONDecoder().decode([ZoteroRawObject].self, from: fixtureData)
            let storedObjects = try rawObjects.map { try ZoteroStoredObject(kind: .item, object: $0) }

            try database.storeRemoteObjects(storedObjects, libraryID: libraryID)

            #expect(try database.objectCount(libraryID: libraryID, kind: .item) == rawObjects.count)
            for original in rawObjects {
                let key = try #require(original.key)
                let fetched = try database.fetchObject(libraryID: libraryID, kind: .item, key: key)
                let reloaded = try #require(fetched)
                #expect(reloaded.current == original.rawValue)
                #expect(reloaded.pristine == original.rawValue)
                #expect(reloaded.version == original.version)
                #expect(reloaded.objectType == original.itemType)
                #expect(reloaded.syncState == .synced)
                #expect(!reloaded.isDeleted)
            }
        }
    }

    @Test("Database migrations are repeatable on an existing file")
    func migrationsAreRepeatable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-db-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "library.sqlite")

        let first = try CitrationDatabase(at: databaseURL)
        let libraryID = try first.upsertLibrary(identity: ZoteroLibraryIdentity(type: "user", remoteID: 1))
        try first.storeRemoteObjects(
            [ZoteroStoredObject(
                kind: .setting,
                key: "fixture-setting",
                version: 1,
                current: .object(["value": .bool(true)])
            )],
            libraryID: libraryID
        )

        let reopened = try CitrationDatabase(at: databaseURL)
        #expect(try reopened.objectCount(libraryID: libraryID) == 1)
        #expect(try reopened.integrityCheck() == "ok")
    }

    // MARK: Private

    private static let requiredSchemaObjects: Set<String> = [
        "annotation_projections",
        "attachment_projections",
        "collection_items",
        "collection_projections",
        "fulltext_content",
        "item_creators",
        "item_projections",
        "item_tags",
        "libraries",
        "library_search",
        "reader_state",
        "synchronization_failures",
        "zotero_objects",
    ]

    private func withTemporaryDatabase(_ body: (CitrationDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-db-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(CitrationDatabase(at: directory.appending(path: "library.sqlite")))
    }

    private func fixtureDirectory() throws -> URL {
        try #require(Bundle.module.resourceURL?.appending(path: "Fixtures/Zotero"))
    }
}
