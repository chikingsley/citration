@testable import CitrationCore
import Foundation
import GRDB
import Testing

// MARK: - LegacyLibraryMigratorTests

@Suite("Legacy library migration")
struct LegacyLibraryMigratorTests {
    // MARK: Internal

    @Test("Populated on-disk legacy stores migrate through a recoverable backup")
    func populatedStoresMigrate() async throws {
        let fixture = try await LegacyFixture.makePopulated()
        defer { fixture.remove() }
        let database = try CitrationDatabase(at: fixture.finalDatabaseURL)
        let migrator = LegacyLibraryMigrator(
            database: database,
            sources: LegacyLibrarySources(applicationDirectory: fixture.legacyDirectory),
            backupDirectory: fixture.backupDirectory
        )

        let report = try migrator.migrateSynchronously()
        let libraryID = try database.upsertLibrary(
            identity: ZoteroLibraryIdentity(type: "local", remoteID: 0)
        )
        try await verifyBackup(report, fixture: fixture)
        let inspection = try verifyCounts(database, libraryID: libraryID)
        try verifyPrimaryItem(database, libraryID: libraryID, fixture: fixture)
        try verifyRelatedRecords(database, libraryID: libraryID, fixture: fixture)
        try await verifyFinalStore(database, fixture: fixture)
        try await verifyIdempotence(
            migrator,
            database: database,
            libraryID: libraryID,
            report: report,
            inspection: inspection
        )
    }

    @Test("A failed real-file migration records failure and safely restarts")
    func failedMigrationRestarts() async throws {
        let fixture = try await LegacyFixture.makePopulated()
        defer { fixture.remove() }
        try Data("{".utf8).write(to: fixture.legacyDirectory.appending(path: "notes.json"), options: .atomic)
        let database = try CitrationDatabase(at: fixture.finalDatabaseURL)
        let migrator = LegacyLibraryMigrator(
            database: database,
            sources: LegacyLibrarySources(applicationDirectory: fixture.legacyDirectory),
            backupDirectory: fixture.backupDirectory
        )

        do {
            _ = try await migrator.migrate()
            Issue.record("Expected invalid on-disk JSON to fail migration")
        } catch {
            #expect(error is DecodingError)
        }

        let libraryID = try database.upsertLibrary(
            identity: ZoteroLibraryIdentity(type: "local", remoteID: 0)
        )
        let failed = try database.inspectLegacyMigration(
            name: LegacyLibraryMigrator.migrationName,
            libraryID: libraryID
        )
        #expect(failed.status == "failed")
        #expect(failed.legacyRecordCount == 0)

        try fixture.notesData.write(
            to: fixture.legacyDirectory.appending(path: "notes.json"),
            options: .atomic
        )
        let report = try await migrator.migrate()
        #expect(report.noteCount == 1)
        #expect(
            try database.inspectLegacyMigration(name: LegacyLibraryMigrator.migrationName, libraryID: libraryID).status
                == "completed"
        )
        #expect(try database.integrityCheck() == "ok")
    }

    // MARK: Private

    private static func isValidZoteroKey(_ key: String) -> Bool {
        ZoteroObjectKey.isValid(key)
    }

    private func verifyBackup(
        _ report: LegacyLibraryMigrationReport,
        fixture: LegacyFixture
    ) async throws {
        #expect(report.itemCount == fixture.items.count)
        #expect(report.collectionCount == 1)
        #expect(report.membershipCount == 1)
        #expect(report.noteCount == 1)
        #expect(report.attachmentCount == 1)
        #expect(report.annotationCount == 1)
        #expect(report.relationshipCount == 1)
        #expect(report.readerProgressCount == 1)
        #expect(FileManager.default.fileExists(atPath: report.backupURL.appending(path: "backup-complete.json").path))
        #expect(try Data(contentsOf: report.backupURL.appending(path: "notes.json")) == fixture.notesData)
        #expect(
            try Data(contentsOf: report.backupURL.appending(path: fixture.attachmentRelativePath))
                == fixture.attachmentData
        )
        let backupStore = try SwiftDataItemStore(storeURL: report.backupURL.appending(path: "items.store"))
        #expect(try await backupStore.exportItems() == fixture.items)
    }

    private func verifyCounts(_ database: CitrationDatabase, libraryID: Int64) throws -> LegacyMigrationInspection {
        let inspection = try database.inspectLegacyMigration(
            name: LegacyLibraryMigrator.migrationName,
            libraryID: libraryID
        )
        #expect(inspection.status == "completed")
        #expect(inspection.legacyRecordCount == 9)
        #expect(inspection.relationshipCount == 1)
        #expect(inspection.readerStateCount == 1)
        #expect(inspection.downloadedAttachmentCount == 1)
        #expect(try database.objectCount(libraryID: libraryID, kind: .collection) == 1)
        #expect(try database.objectCount(libraryID: libraryID, kind: .item) == 5)
        let migratedKeys = try database.databaseQueue.read { sqlDatabase in
            try String.fetchAll(sqlDatabase, sql: "SELECT object_key FROM zotero_objects WHERE library_id = ?", arguments: [libraryID])
        }
        #expect(migratedKeys.allSatisfy(Self.isValidZoteroKey))
        return inspection
    }

    private func verifyPrimaryItem(
        _ database: CitrationDatabase,
        libraryID: Int64,
        fixture: LegacyFixture
    ) throws {
        let firstItem = try #require(fixture.items.first { $0.title == "A Real Legacy Article" })
        let itemKey = try #require(try database.legacyMigratedObjectKey(
            libraryID: libraryID,
            entityKind: "item",
            legacyID: firstItem.id.uuidString
        ))
        let storedItem = try #require(try database.fetchObject(libraryID: libraryID, kind: .item, key: itemKey))
        let projectedItem = try #require(try database.fetchProjectedItem(libraryID: libraryID, key: itemKey))
        #expect(storedItem.version == 0)
        #expect(storedItem.syncState == .dirty)
        #expect(projectedItem.title == firstItem.title)
        #expect(projectedItem.tags.map(\.value) == firstItem.tags)
        #expect(projectedItem.collectionKeys.count == 1)

        let itemPayload = try #require(try database.legacyRecordPayload(
            libraryID: libraryID,
            entityKind: "item",
            legacyID: firstItem.id.uuidString
        ))
        #expect(try JSONDecoder().decode(BCItem.self, from: itemPayload) == firstItem)
    }

    private func verifyRelatedRecords(
        _ database: CitrationDatabase,
        libraryID: Int64,
        fixture: LegacyFixture
    ) throws {
        let notePayload = try #require(try database.legacyRecordPayload(
            libraryID: libraryID,
            entityKind: "note",
            legacyID: fixture.note.id.uuidString
        ))
        #expect(try JSONDecoder().decode(LibraryNote.self, from: notePayload) == fixture.note)

        let annotationKey = try #require(try database.legacyMigratedObjectKey(
            libraryID: libraryID,
            entityKind: "annotation",
            legacyID: fixture.annotation.id.uuidString
        ))
        let projectedAnnotation = try #require(
            try database.fetchProjectedItem(libraryID: libraryID, key: annotationKey)?.annotation
        )
        #expect(projectedAnnotation.positionJSON.contains("\"pageIndex\":2"))
        #expect(projectedAnnotation.comment == fixture.annotation.note)

        let attachmentKey = try #require(try database.legacyMigratedObjectKey(
            libraryID: libraryID,
            entityKind: "attachment",
            legacyID: fixture.attachmentLegacyKey
        ))
        let storedAttachmentPath = try #require(
            try database.localAttachmentPath(libraryID: libraryID, itemKey: attachmentKey)
        )
        #expect(
            URL(filePath: storedAttachmentPath).resolvingSymlinksInPath()
                == fixture.attachmentURL.resolvingSymlinksInPath()
        )

        let progressPayload = try #require(try database.legacyRecordPayload(
            libraryID: libraryID,
            entityKind: "readerProgress",
            legacyID: fixture.attachmentLegacyKey
        ))
        #expect(try JSONDecoder().decode(ReaderProgress.self, from: progressPayload) == fixture.readerProgress)
        #expect(try database.integrityCheck() == "ok")
    }

    private func verifyIdempotence(
        _ migrator: LegacyLibraryMigrator,
        database: CitrationDatabase,
        libraryID: Int64,
        report: LegacyLibraryMigrationReport,
        inspection: LegacyMigrationInspection
    ) async throws {
        let repeatedReport = try await migrator.migrate()
        #expect(repeatedReport == report)
        #expect(
            try database.inspectLegacyMigration(name: LegacyLibraryMigrator.migrationName, libraryID: libraryID)
                == inspection
        )
    }

    private func verifyFinalStore(
        _ database: CitrationDatabase,
        fixture: LegacyFixture
    ) async throws {
        let store = try CitrationLibraryStore(
            database: database,
            attachmentsDirectory: fixture.legacyDirectory.appending(path: "attachments", directoryHint: .isDirectory)
        )
        let item = try #require(fixture.items.first { $0.title == "A Real Legacy Article" })
        #expect(await Set(store.listItems().map(\.id)) == Set(fixture.items.map(\.id)))
        #expect(try await store.snapshot().collections.count == 1)
        #expect(try await store.snapshot().memberships.count == 1)
        #expect(try await store.listNotes(itemID: item.id) == [fixture.note])
        let attachment = try #require(try await store.listAttachments(for: item.id).first)
        #expect(attachment.localURL.resolvingSymlinksInPath() == fixture.attachmentURL.resolvingSymlinksInPath())
        let annotation = try #require(
            try await store.listAnnotations(itemID: item.id, attachmentKey: attachment.objectKey).first
        )
        #expect(annotation.id == fixture.annotation.id)
        #expect(annotation.location == fixture.annotation.location)
        #expect(annotation.attachmentKey == attachment.objectKey)
        let progress = try #require(try await store.progress(for: attachment.objectKey))
        #expect(progress.itemID == fixture.readerProgress.itemID)
        #expect(progress.location == fixture.readerProgress.location)
        #expect(progress.attachmentKey == attachment.objectKey)
    }
}

// MARK: - LegacyFixture

private struct LegacyFixture {
    // MARK: Internal

    let rootDirectory: URL
    let legacyDirectory: URL
    let backupDirectory: URL
    let finalDatabaseURL: URL
    let items: [BCItem]
    let note: LibraryNote
    let annotation: LibraryAnnotation
    let readerProgress: ReaderProgress
    let notesData: Data
    let attachmentURL: URL
    let attachmentData: Data
    let attachmentLegacyKey: String
    let attachmentRelativePath: String

    static func makePopulated() async throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "citration-legacy-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        let legacy = root.appending(path: "legacy", directoryHint: .isDirectory)
        let backups = root.appending(path: "backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let items = makeItems()
        let storedItems = try await writeItems(items, to: legacy)
        let metadata = makeMetadata(first: items[0], second: items[1])
        let notesData = try writeMetadata(metadata, to: legacy)
        let attachment = try writeAttachment(item: items[0], to: legacy)

        return Self(
            rootDirectory: root,
            legacyDirectory: legacy,
            backupDirectory: backups,
            finalDatabaseURL: root.appending(path: "library.sqlite"),
            items: storedItems,
            note: metadata.note,
            annotation: metadata.annotation,
            readerProgress: metadata.progress,
            notesData: notesData,
            attachmentURL: attachment.url,
            attachmentData: attachment.data,
            attachmentLegacyKey: metadata.attachmentKey,
            attachmentRelativePath: attachment.relativePath
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    // MARK: Private

    private static func makeItems() -> [BCItem] {
        let article = BCItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            title: "A Real Legacy Article",
            identifiers: [
                Identifier(type: .doi, value: "10.1000/legacy"),
                Identifier(type: .url, value: "https://example.test/legacy"),
            ],
            itemType: .article,
            creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
            publicationYear: 1843,
            tags: ["history", "computing"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let book = BCItem(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            title: "A Real Legacy Book",
            identifiers: [Identifier(type: .isbn, value: "9780000000002")],
            itemType: .book,
            creators: [Creator(literalName: "Fixture Press")],
            publicationYear: 2024,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
        return [article, book]
    }

    private static func writeItems(_ items: [BCItem], to directory: URL) async throws -> [BCItem] {
        let store = try SwiftDataItemStore(storeURL: directory.appending(path: "items.store"))
        for item in items {
            await store.upsert(item)
        }
        return try await store.exportItems()
    }

    private static func makeMetadata(first: BCItem, second: BCItem) -> LegacyMetadataFixture {
        let collection = LibraryCollection(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
            name: "Migration Evidence",
            createdAt: Date(timeIntervalSince1970: 1_700_000_400),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let membership = LibraryCollectionMembership(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
            collectionID: collection.id,
            itemID: first.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_600)
        )
        let note = LibraryNote(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
            itemID: first.id,
            text: "A preserved legacy note.",
            createdAt: Date(timeIntervalSince1970: 1_700_000_700),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_800)
        )
        let attachmentKey = "\(first.id.uuidString)/legacy-evidence.pdf"
        return LegacyMetadataFixture(
            snapshot: .init(collections: [collection], memberships: [membership]),
            note: note,
            annotation: makeAnnotation(item: first, attachmentKey: attachmentKey),
            relationship: makeRelationship(first: first, second: second),
            progress: makeProgress(item: first, attachmentKey: attachmentKey),
            attachmentKey: attachmentKey
        )
    }

    private static func makeAnnotation(item: BCItem, attachmentKey: String) -> LibraryAnnotation {
        LibraryAnnotation(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID(),
            itemID: item.id,
            attachmentKey: attachmentKey,
            kind: .highlight,
            location: .page(3),
            selectedText: "real selected text",
            note: "Preserved annotation comment",
            color: .blue,
            createdAt: Date(timeIntervalSince1970: 1_700_000_900),
            updatedAt: Date(timeIntervalSince1970: 1_700_001_000)
        )
    }

    private static func makeRelationship(first: BCItem, second: BCItem) -> LibraryRelationship {
        LibraryRelationship(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777") ?? UUID(),
            sourceItemID: first.id,
            targetItemID: second.id,
            kind: .cites,
            confidence: 0.9,
            note: "Verified relationship"
        )
    }

    private static func makeProgress(item: BCItem, attachmentKey: String) -> ReaderProgress {
        ReaderProgress(
            itemID: item.id,
            attachmentKey: attachmentKey,
            location: .page(3),
            fractionComplete: 0.25,
            updatedAt: Date(timeIntervalSince1970: 1_700_001_100)
        )
    }

    private static func writeMetadata(_ metadata: LegacyMetadataFixture, to directory: URL) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata.snapshot)
            .write(to: directory.appending(path: "collections.json"), options: .atomic)
        let notesData = try encoder.encode([metadata.note])
        try notesData.write(to: directory.appending(path: "notes.json"), options: .atomic)
        try encoder.encode([metadata.annotation])
            .write(to: directory.appending(path: "annotations.json"), options: .atomic)
        try encoder.encode([metadata.relationship])
            .write(to: directory.appending(path: "relationships.json"), options: .atomic)
        try encoder.encode([metadata.progress])
            .write(to: directory.appending(path: "reader-progress.json"), options: .atomic)
        return notesData
    }

    private static func writeAttachment(item: BCItem, to directory: URL) throws -> LegacyAttachmentFixture {
        let relativePath = "attachments/\(item.id.uuidString)--evidence/legacy-evidence.pdf"
        let url = directory.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data("%PDF-1.7\nreal migration fixture\n%%EOF\n".utf8)
        try data.write(to: url, options: .atomic)
        return LegacyAttachmentFixture(url: url, data: data, relativePath: relativePath)
    }
}

// MARK: - LegacyMetadataFixture

private struct LegacyMetadataFixture {
    let snapshot: LibraryCollectionSnapshot
    let note: LibraryNote
    let annotation: LibraryAnnotation
    let relationship: LibraryRelationship
    let progress: ReaderProgress
    let attachmentKey: String
}

// MARK: - LegacyAttachmentFixture

private struct LegacyAttachmentFixture {
    let url: URL
    let data: Data
    let relativePath: String
}
