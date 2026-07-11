@testable import CitrationCore
import Foundation
import Testing

@Suite("Library preservation snapshot")
struct PreservationSnapshotTests {
    @Test("captured objects and unsupported raw data remain visibly inspectable")
    func capturedAndUnsupportedObjectsAreVisible() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let libraryID = try fixture.database.upsertLibrary(
            identity: ZoteroLibraryIdentity(type: "user", remoteID: 42)
        )
        let collections = try fixture.capturedCollections()
        let items = try fixture.capturedItems()
        try fixture.database.storeRemoteCollections(collections, libraryID: libraryID)
        try fixture.database.storeRemoteItems(items, libraryID: libraryID)

        let fullTextURL = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/Zotero/fulltext.json")
        )
        let fullTextFixture = try #require(
            try ZoteroJSON.decode(Data(contentsOf: fullTextURL)).objectValue
        )
        let fullTextKey = try #require(fullTextFixture["itemKey"]?.stringValue)
        let fullTextData = try #require(fullTextFixture["data"])
        try fixture.database.storeRemoteFullText(
            itemKey: fullTextKey,
            version: 1291,
            response: fullTextData,
            libraryID: libraryID
        )
        try fixture.database.storeRemoteObjects(
            [
                ZoteroStoredObject(
                    kind: .setting,
                    key: "readerSettings",
                    version: 7,
                    current: .object(["value": .object(["theme": .string("dark")])])
                ),
                ZoteroStoredObject(
                    kind: ZoteroObjectKind(rawValue: "future-object"),
                    key: "FUTURE1",
                    version: 3,
                    objectType: "futureType",
                    current: .object(["unknown": .bool(true)])
                ),
                ZoteroStoredObject(
                    kind: .item,
                    key: "DELETED1",
                    version: 9,
                    objectType: "book",
                    current: .object(["key": .string("DELETED1")]),
                    isDeleted: true
                ),
            ],
            libraryID: libraryID
        )

        let snapshot = try fixture.database.libraryPreservationSnapshot(libraryID: libraryID)

        #expect(snapshot.collectionCount == collections.count)
        #expect(snapshot.tagCount > 0)
        #expect(snapshot.attachments.isEmpty == false)
        #expect(snapshot.fullTextCount == 1)
        #expect(snapshot.attachments.contains { $0.key == fullTextKey && $0.fullTextVersion == 1291 })
        #expect(snapshot.settings.map(\.key) == ["readerSettings"])
        #expect(snapshot.settings.first?.value == .object(["value": .object(["theme": .string("dark")])]))
        #expect(snapshot.deletedObjects.map(\.key) == ["DELETED1"])
        #expect(snapshot.unsupportedObjects.map(\.key) == ["FUTURE1"])
        #expect(snapshot.objectCounts.first { $0.kind == "item" }?.count == items.count)
    }
}
