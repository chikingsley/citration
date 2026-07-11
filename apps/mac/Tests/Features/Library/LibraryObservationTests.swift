@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("Library database observation")
@MainActor
struct LibraryObservationTests {
    @Test("Sync status observes pending work in the real app database")
    func syncStatusObservation() async throws {
        let model = makeAppModel(initialItems: [BCItem(title: "Pending Fixture")])

        try await waitUntil {
            model.syncStatus?.pendingUploadCount == 1
        }

        #expect(model.syncStatus?.currentVersion == 0)
        #expect(model.syncStatus?.failures.isEmpty == true)
    }

    @Test("A committed GRDB item refreshes the visible library without a command callback")
    func committedItemRefreshesVisibleLibrary() async throws {
        let model = makeAppModel()
        try await waitUntil {
            model.libraryObservationRevision > 0
        }
        let initialRevision = model.libraryObservationRevision
        let item = BCItem(title: "Observed Database Item")

        await model.store.upsert(item)

        try await waitUntil {
            model.libraryObservationRevision > initialRevision
                && model.items.contains(where: { $0.identity.appUUID == item.id })
        }
        let visibleItem = try #require(model.items.first { $0.identity.appUUID == item.id })
        let store = try #require(model.store as? CitrationLibraryStore)
        #expect(model.selectedItemID == item.id)
        #expect(model.selectedItemIdentity == visibleItem.identity)
        #expect(visibleItem.identity.libraryID == store.initialLibraryID)
        #expect(!visibleItem.identity.objectKey.isEmpty)
    }

    @Test("Saved searches and trash counts refresh from the observed database")
    func navigationRefreshesFromDatabase() async throws {
        let model = makeAppModel()
        let store = try #require(model.store as? CitrationLibraryStore)
        try await waitUntil {
            model.navigationObservationRevision > 0
        }
        let initialRevision = model.navigationObservationRevision
        try model.database.storeRemoteObjects(
            [
                ZoteroStoredObject(
                    kind: .search,
                    key: "SEARCH01",
                    version: 1,
                    current: .object([
                        "key": .string("SEARCH01"),
                        "data": .object(["name": .string("Recently Added")]),
                    ])
                ),
                ZoteroStoredObject(
                    kind: .item,
                    key: "DELETED1",
                    version: 2,
                    current: .object([
                        "key": .string("DELETED1"),
                        "data": .object(["deleted": .bool(true)]),
                    ]),
                    isDeleted: true
                ),
            ],
            libraryID: store.initialLibraryID
        )

        try await waitUntil {
            model.navigationObservationRevision > initialRevision
        }
        #expect(model.savedSearches == [
            ZoteroSavedSearchSummary(key: "SEARCH01", name: "Recently Added")
        ])
        #expect(model.deletedItemCount == 1)
    }

    @Test("Nested collection sources retain their hierarchy")
    func nestedCollectionTree() throws {
        let root = LibraryCollection(id: UUID(), name: "Root")
        let child = LibraryCollection(id: UUID(), name: "Child", parentID: root.id)
        let grandchild = LibraryCollection(id: UUID(), name: "Grandchild", parentID: child.id)

        let roots = [grandchild, child, root].collectionTree()

        let rootNode = try #require(roots.first)
        let childNode = try #require(rootNode.children?.first)
        #expect(rootNode.collection == root)
        #expect(childNode.collection == child)
        #expect(childNode.children?.first?.collection == grandchild)
    }

    @Test("Native field edits retain synchronized identity in the real app database")
    func fieldEditsRetainSynchronizedIdentity() async throws {
        let item = BCItem(title: "Before Edit", itemType: .book)
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        let identity = try #require(model.selectedItemIdentity)

        let updated = try await model.updateItemFields(
            identity: identity,
            updates: [
                ZoteroItemFieldUpdate(field: "title", value: .string("After Edit")),
                ZoteroItemFieldUpdate(field: "publisher", value: .string("Real SQLite Press")),
            ]
        )

        #expect(updated.identity == identity)
        #expect(model.selectedItemIdentity == identity)
        #expect(model.selectedItem?.title == "After Edit")
        #expect(model.selectedLibraryItem?.projected.fields["publisher"] == .string("Real SQLite Press"))
    }
}
