@testable import CitrationCore
import Foundation
import Testing

// MARK: - CitrationLibraryStoreTests

@Suite("GRDB library store")
struct CitrationLibraryStoreTests {
    @Test("Every local library feature persists through one real database and real files")
    func allFeaturesPersist() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = try fixture.makeStore()
        let items = fixture.items

        for item in items {
            await store.upsert(item)
        }
        let collection = try await store.createCollection(name: "Evidence", parentID: nil)
        let membership = try await store.addItem(items[0].id, to: collection.id)
        let note = try await store.upsert(LibraryNote(itemID: items[0].id, text: "Database note"))
        let attachment = try await store.importFile(from: fixture.sourceFile, for: items[0])
        let annotation = try await store.upsert(LibraryAnnotation(
            itemID: items[0].id,
            attachmentKey: attachment.objectKey,
            kind: .highlight,
            location: .page(4),
            selectedText: "Persisted selection",
            note: "Persisted comment",
            color: .green
        ))
        let progress = try await store.upsert(ReaderProgress(
            itemID: items[0].id,
            attachmentKey: attachment.objectKey,
            location: .page(4),
            fractionComplete: 0.4
        ))
        let relationship = try await store.upsert(LibraryRelationship(
            sourceItemID: items[0].id,
            targetItemID: items[1].id,
            kind: .cites,
            confidence: 1
        ))

        let reopened = try fixture.makeStore()
        #expect(await Set(reopened.listItems().map(\.id)) == Set(items.map(\.id)))
        let snapshot = try await reopened.snapshot()
        #expect(snapshot.collections == [collection])
        #expect(snapshot.memberships == [membership])
        #expect(try await reopened.listNotes(itemID: items[0].id) == [note])
        #expect(try await reopened.listAttachments(for: items[0].id) == [attachment])
        #expect(
            try await reopened.listAnnotations(itemID: items[0].id, attachmentKey: attachment.objectKey)
                == [annotation]
        )
        #expect(try await reopened.progress(for: attachment.objectKey) == progress)
        #expect(try await reopened.listRelationships() == [relationship])
        #expect(try fixture.database.integrityCheck() == "ok")
    }

    @Test("GRDB mutations remove projections without losing synchronization tombstones")
    func removalsPersist() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = try fixture.makeStore()
        for item in fixture.items {
            await store.upsert(item)
        }
        let collection = try await store.createCollection(name: "Temporary", parentID: nil)
        _ = try await store.addItem(fixture.items[0].id, to: collection.id)
        let note = try await store.upsert(LibraryNote(itemID: fixture.items[0].id, text: "Remove"))

        try await store.remove(id: note.id)
        try await store.removeCollection(id: collection.id)
        await store.removeItem(id: fixture.items[0].id)

        #expect(try await store.listNotes(itemID: fixture.items[0].id).isEmpty)
        #expect(try await store.snapshot().collections.isEmpty)
        #expect(await store.listItems().map(\.id) == [fixture.items[1].id])
        #expect(try fixture.database.integrityCheck() == "ok")
    }
}

// MARK: - StoreFixture

private struct StoreFixture {
    // MARK: Lifecycle

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "citration-grdb-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        database = try CitrationDatabase(at: root.appending(path: "library.sqlite"))
        sourceFile = root.appending(path: "source.pdf")
        try Data("%PDF-1.7\nreal store fixture\n%%EOF\n".utf8).write(to: sourceFile)
    }

    // MARK: Internal

    let root: URL
    let database: CitrationDatabase
    let sourceFile: URL
    let items: [BCItem] = [
        BCItem(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID(),
            title: "First persisted item",
            identifiers: [Identifier(type: .doi, value: "10.1000/first")],
            itemType: .article,
            creators: [Creator(givenName: "First", familyName: "Author")],
            publicationYear: 2025,
            tags: ["one"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        ),
        BCItem(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID(),
            title: "Second persisted item",
            itemType: .book,
            publicationYear: 2026,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
        ),
    ]

    func makeStore() throws -> CitrationLibraryStore {
        try CitrationLibraryStore(
            database: database,
            attachmentsDirectory: root.appending(path: "attachments", directoryHint: .isDirectory)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
