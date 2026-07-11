@testable import CitrationCore
import Foundation
import Testing

// MARK: - LibrarySearchTests

@Suite("Complete library search")
struct LibrarySearchTests {
    @Test("every indexed child and collection resolves to its owning library item")
    func everyIndexedRepresentationResolvesToTopLevelItem() async throws {
        let fixture = try SearchFixture()
        defer { fixture.remove() }

        for query in [
            "Synchro",
            "Love",
            "retriev",
            "marginalia",
            "geometry",
            "comment",
            "downloaded-document",
            "Memory Palace",
        ] {
            #expect(try fixture.search(query) == ["ROOT0001"])
        }
        #expect(try fixture.search("Love", field: .creator) == ["ROOT0001"])
        #expect(try fixture.search("Memory", field: .title).isEmpty)
        #expect(try fixture.search("unrelated") == ["ROOT0002"])

        let snapshot = try await fixture.store.snapshot()
        let storedRoot = try #require(
            await fixture.store.listLibraryItems().first { $0.identity.objectKey == "ROOT0001" }
        )
        let storedCollection = try #require(snapshot.collections.first)
        #expect(snapshot.memberships.map(\.itemID) == [storedRoot.identity.appUUID])
        #expect(snapshot.memberships.map(\.collectionID) == [storedCollection.id])
    }
}

// MARK: - SearchFixture

private struct SearchFixture {
    // MARK: Lifecycle

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "citration-complete-search-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        database = try CitrationDatabase(at: rootDirectory.appending(path: "library.sqlite"))
        identity = ZoteroLibraryIdentity(type: "user", remoteID: 42)
        libraryID = try database.upsertLibrary(identity: identity, name: "Search Fixture")
        let objects = try Self.makeObjects()
        try database.storeRemoteCollections([objects.collection], libraryID: libraryID)
        try database.storeRemoteItems(objects.items, libraryID: libraryID)
        try database.ensureAppIdentities(
            collections: [objects.collection],
            items: objects.items,
            libraryID: libraryID
        )
        try database.storeRemoteFullText(
            itemKey: "ATTA0001",
            version: 4,
            response: .object([
                "content": .string("downloaded-document-signal"),
                "indexedPages": .integer(1),
                "totalPages": .integer(1),
            ]),
            libraryID: libraryID
        )
        store = try CitrationLibraryStore(
            database: database,
            attachmentsDirectory: rootDirectory.appending(path: "attachments", directoryHint: .isDirectory),
            libraryIdentity: identity,
            libraryName: "Search Fixture"
        )
    }

    // MARK: Internal

    let rootDirectory: URL
    let database: CitrationDatabase
    let identity: ZoteroLibraryIdentity
    let libraryID: Int64
    let store: CitrationLibraryStore

    func remove() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func search(_ query: String, field: LibrarySearchField = .all) throws -> [String] {
        try database.searchLibraryItemKeys(libraryID: libraryID, query: query, field: field)
    }

    // MARK: Private

    private static func makeObjects() throws -> (collection: ZoteroRawObject, items: [ZoteroRawObject]) {
        let root = try item(
            key: "ROOT0001",
            type: "book",
            values: [
                "title": .string("Synchronized Search Atlas"),
                "creators": .array([.object([
                    "creatorType": .string("author"),
                    "firstName": .string("Ada"),
                    "lastName": .string("Lovelace"),
                ])]),
                "tags": .array([.object(["tag": .string("retrieval-marker")])]),
                "collections": .array([.string("COLL0001")]),
            ]
        )
        let note = try item(
            key: "NOTE0001",
            type: "note",
            values: ["parentItem": .string("ROOT0001"), "note": .string("<p>marginalia-signal</p>")]
        )
        let attachment = try item(
            key: "ATTA0001",
            type: "attachment",
            values: [
                "parentItem": .string("ROOT0001"),
                "linkMode": .string("imported_file"),
                "contentType": .string("application/pdf"),
                "filename": .string("atlas.pdf"),
            ]
        )
        let annotation = try item(
            key: "ANNO0001",
            type: "annotation",
            values: [
                "parentItem": .string("ATTA0001"),
                "annotationType": .string("highlight"),
                "annotationText": .string("geometry-signal"),
                "annotationComment": .string("comment-signal"),
            ]
        )
        let unrelated = try item(
            key: "ROOT0002",
            type: "book",
            values: ["title": .string("Unrelated Work")]
        )
        let collection = try object(
            key: "COLL0001",
            values: ["name": .string("Memory Palace Collection"), "parentCollection": .bool(false)]
        )
        return (collection, [root, note, attachment, annotation, unrelated])
    }

    private static func item(key: String, type: String, values: [String: JSONValue]) throws -> ZoteroRawObject {
        var values = values
        values["itemType"] = .string(type)
        values["tags"] = values["tags"] ?? .array([])
        values["collections"] = values["collections"] ?? .array([])
        return try object(key: key, values: values)
    }

    private static func object(key: String, values: [String: JSONValue]) throws -> ZoteroRawObject {
        var data = values
        data["key"] = .string(key)
        data["version"] = .integer(4)
        return try ZoteroRawObject(rawValue: .object([
            "key": .string(key),
            "version": .integer(4),
            "data": .object(data),
        ]))
    }
}
