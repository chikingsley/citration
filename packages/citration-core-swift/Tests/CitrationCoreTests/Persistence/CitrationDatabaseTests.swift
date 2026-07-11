@testable import CitrationCore
import Foundation
import Testing

// MARK: - CitrationDatabaseTests

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

    @Test("Captured objects populate typed relationship and document projections")
    func capturedObjectsPopulateProjections() throws {
        try withTemporaryDatabase { database in
            let libraryID = try database.upsertLibrary(
                identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
                currentVersion: 1291
            )
            let collections = try capturedObjects(filename: "collections.json")
            let items = try capturedObjects(filename: "items.json")

            try database.storeRemoteCollections(collections, libraryID: libraryID)
            try database.storeRemoteItems(items, libraryID: libraryID)

            var creatorRoles = Set<String>()
            var contentTypes = Set<String>()
            var annotationTypes = Set<String>()

            for object in items {
                let key = try #require(object.key)
                let fetched = try database.fetchProjectedItem(libraryID: libraryID, key: key)
                let projected = try #require(fetched)
                #expect(projected.itemType == object.itemType)
                #expect(projected.fields == object.data)
                let expectedIdentifiers = ["DOI", "ISBN", "ISSN", "PMID", "PMCID", "url"].compactMap { field in
                    object.data[field]?.stringValue.flatMap { value in
                        value.isEmpty ? nil : ZoteroProjectedIdentifier(type: field, value: value)
                    }
                }
                #expect(projected.identifiers == expectedIdentifiers)
                #expect(projected.parentItemKey == object.data["parentItem"]?.stringValue)
                #expect(projected.collectionKeys == object.data["collections"]?.arrayValue?.compactMap(\.stringValue) ?? [])

                creatorRoles.formUnion(projected.creators.map(\.creatorType))
                if let attachment = projected.attachment {
                    contentTypes.insert(attachment.contentType)
                }
                if let annotation = projected.annotation {
                    annotationTypes.insert(annotation.type)
                    #expect(annotation.positionJSON == object.data["annotationPosition"]?.stringValue)
                }
            }

            #expect(creatorRoles.isSuperset(of: ["author", "contributor", "editor"]))
            #expect(contentTypes.isSuperset(of: ["application/epub+zip", "application/pdf", "text/html"]))
            #expect(annotationTypes == ["highlight", "ink", "note", "underline"])
            #expect(try database.integrityCheck() == "ok")
        }
    }

    @Test("Backup produces an independently readable integrity-checked database")
    func backupIsRestorable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-db-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try CitrationDatabase(at: directory.appending(path: "source.sqlite"))
        let libraryID = try source.upsertLibrary(identity: ZoteroLibraryIdentity(type: "user", remoteID: 1))
        try source.storeRemoteObjects(
            [ZoteroStoredObject(
                kind: .setting,
                key: "fixture-setting",
                version: 3,
                current: .object(["value": .string("fixture")])
            )],
            libraryID: libraryID
        )

        let backupURL = directory.appending(path: "backup.sqlite")
        try source.backup(to: backupURL)

        let restored = try CitrationDatabase(at: backupURL)
        #expect(try restored.objectCount(libraryID: libraryID) == 1)
        #expect(try restored.integrityCheck() == "ok")
    }

    @Test("Captured full text is durable and participates in FTS5 search")
    func capturedFullTextIsSearchable() throws {
        try withTemporaryDatabase { database in
            let libraryID = try database.upsertLibrary(
                identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
                currentVersion: 1291
            )
            try database.storeRemoteCollections(capturedObjects(filename: "collections.json"), libraryID: libraryID)
            try database.storeRemoteItems(capturedObjects(filename: "items.json"), libraryID: libraryID)

            let fixture = try ZoteroJSON.decode(
                Data(contentsOf: fixtureDirectory().appending(path: "fulltext.json"))
            ).objectValue ?? [:]
            let itemKey = try #require(fixture["itemKey"]?.stringValue)
            let response = try #require(fixture["data"])

            try database.storeRemoteFullText(
                itemKey: itemKey,
                version: 1291,
                response: response,
                libraryID: libraryID
            )

            let fetched = try database.fetchFullText(libraryID: libraryID, itemKey: itemKey)
            let fullText = try #require(fetched)
            #expect(fullText.content == response.objectValue?["content"]?.stringValue)
            #expect(fullText.indexedPages == response.objectValue?["indexedPages"]?.integerValue.map(Int.init))
            #expect(try database.searchObjectKeys(libraryID: libraryID, query: "fixture").contains(itemKey))
        }
    }

    @Test("Database observation emits initial and committed library snapshots")
    func databaseObservationEmitsSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-db-observation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try CitrationDatabase(at: directory.appending(path: "library.sqlite"))
        let libraryID = try database.upsertLibrary(identity: ZoteroLibraryIdentity(type: "user", remoteID: 1))
        let collections = try capturedObjects(filename: "collections.json")
        let items = try capturedObjects(filename: "items.json")
        let recorder = ObservationRecorder()
        let observation = database.observeLibraryItems(
            libraryID: libraryID,
            onError: { error in
                Task { await recorder.record(error: error) }
            },
            onChange: { snapshot in
                Task { await recorder.record(snapshot: snapshot) }
            }
        )

        while await recorder.snapshotCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await recorder.snapshots == [[]])

        try database.storeRemoteCollections(collections, libraryID: libraryID)
        try database.storeRemoteItems(items, libraryID: libraryID)
        while await recorder.snapshotCount < 2, await recorder.errorDescription == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        observation.cancel()
        #expect(await recorder.errorDescription == nil)
        let snapshots = await recorder.snapshots
        let updated = try #require(snapshots.last)
        #expect(updated.count == items.count)
        #expect(updated.map(\.title) == updated.map(\.title).sorted {
            $0.localizedCaseInsensitiveCompare($1) != .orderedDescending
        })
    }

    // MARK: Private

    private static let requiredSchemaObjects: Set<String> = [
        "annotation_projections",
        "app_relationships",
        "app_object_identity",
        "app_collection_memberships",
        "attachment_projections",
        "collection_items",
        "collection_projections",
        "fulltext_content",
        "item_creators",
        "item_fields",
        "item_identifiers",
        "item_projections",
        "item_tags",
        "libraries",
        "library_search",
        "legacy_migration_runs",
        "legacy_records",
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

    private func capturedObjects(filename: String) throws -> [ZoteroRawObject] {
        try JSONDecoder().decode(
            [ZoteroRawObject].self,
            from: Data(contentsOf: fixtureDirectory().appending(path: filename))
        )
    }
}

// MARK: - ObservationRecorder

private actor ObservationRecorder {
    private(set) var snapshots: [[ZoteroLibraryItemSummary]] = []
    private(set) var errorDescription: String?

    var snapshotCount: Int {
        snapshots.count
    }

    func record(snapshot: [ZoteroLibraryItemSummary]) {
        snapshots.append(snapshot)
    }

    func record(error: any Error) {
        errorDescription = String(describing: error)
    }
}
