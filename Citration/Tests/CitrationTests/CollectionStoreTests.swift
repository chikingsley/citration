import Testing
import Foundation
@testable import Citration
import CitrationCore

@Suite("LocalCollectionStore")
struct CollectionStoreTests {
    @Test("creates collections and persists memberships")
    func createsCollectionsAndPersistsMemberships() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let storeURL = directory.appendingPathComponent("collections.json")
        let store = try LocalCollectionStore(storeURL: storeURL)

        let collection = try await store.createCollection(name: "  Research   Queue ")
        let itemID = UUID()
        _ = try await store.addItem(itemID, to: collection.id)

        let reloadedStore = try LocalCollectionStore(storeURL: storeURL)
        let snapshot = try await reloadedStore.snapshot()

        #expect(snapshot.collections.first?.name == "Research Queue")
        #expect(snapshot.memberships.first?.collectionID == collection.id)
        #expect(snapshot.memberships.first?.itemID == itemID)
    }

    @Test("duplicate collection names receive suffixes")
    func duplicateCollectionNamesReceiveSuffixes() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalCollectionStore(storeURL: directory.appendingPathComponent("collections.json"))

        let first = try await store.createCollection(name: "Papers")
        let second = try await store.createCollection(name: "papers")

        #expect(first.name == "Papers")
        #expect(second.name == "papers 2")
    }

    @Test("removing collection removes its memberships")
    func removingCollectionRemovesMemberships() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalCollectionStore(storeURL: directory.appendingPathComponent("collections.json"))
        let collection = try await store.createCollection(name: "Temporary")
        _ = try await store.addItem(UUID(), to: collection.id)

        try await store.removeCollection(id: collection.id)
        let snapshot = try await store.snapshot()

        #expect(snapshot.collections.isEmpty)
        #expect(snapshot.memberships.isEmpty)
    }
}

private extension CollectionStoreTests {
    func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-collection-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
