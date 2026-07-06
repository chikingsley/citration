@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - RelationshipStoreTests

@Suite("LocalRelationshipStore")
struct RelationshipStoreTests {
    @Test("stores and lists relationships touching an item")
    func storesAndListsRelationshipsTouchingItem() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let storeURL = directory.appendingPathComponent("relationships.json")
        let store = try LocalRelationshipStore(storeURL: storeURL)
        let sourceID = UUID()
        let targetID = UUID()
        let unrelatedID = UUID()
        let saved = try await store.upsert(
            LibraryRelationship(
                sourceItemID: sourceID,
                targetItemID: targetID,
                kind: .series,
                confidence: 1.25,
                note: "  Volume 2  "
            )
        )
        _ = try await store.upsert(
            LibraryRelationship(
                sourceItemID: unrelatedID,
                targetItemID: UUID(),
                kind: .sameTopic,
                confidence: 0.7
            )
        )

        let reloadedStore = try LocalRelationshipStore(storeURL: storeURL)
        let relationships = try await reloadedStore.listRelationships(itemID: targetID)

        #expect(relationships == [saved])
        #expect(relationships.first?.confidence == 1)
        #expect(relationships.first?.note == "Volume 2")
    }

    @Test("upsert deduplicates source target and kind")
    func upsertDeduplicatesSourceTargetAndKind() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalRelationshipStore(storeURL: directory.appendingPathComponent("relationships.json"))
        let sourceID = UUID()
        let targetID = UUID()
        let original = try await store.upsert(
            LibraryRelationship(sourceItemID: sourceID, targetItemID: targetID, kind: .cites, confidence: 0.4)
        )

        let duplicate = try await store.upsert(
            LibraryRelationship(sourceItemID: sourceID, targetItemID: targetID, kind: .cites, confidence: 0.9)
        )
        let relationships = try await store.listRelationships()

        #expect(duplicate.id == original.id)
        #expect(relationships.count == 1)
        #expect(relationships.first?.confidence == 0.9)
    }

    @Test("removeRelationships deletes links touching item IDs")
    func removeRelationshipsDeletesLinksTouchingItemIDs() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalRelationshipStore(storeURL: directory.appendingPathComponent("relationships.json"))
        let removedID = UUID()
        let keptSourceID = UUID()
        _ = try await store.upsert(
            LibraryRelationship(sourceItemID: removedID, targetItemID: UUID(), kind: .userLinked, confidence: 1)
        )
        _ = try await store.upsert(
            LibraryRelationship(sourceItemID: keptSourceID, targetItemID: UUID(), kind: .sameTopic, confidence: 1)
        )

        try await store.removeRelationships(itemIDs: [removedID])

        #expect(try await store.listRelationships(itemID: removedID).isEmpty)
        #expect(try await store.listRelationships(itemID: keptSourceID).count == 1)
    }
}

private extension RelationshipStoreTests {
    func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-relationship-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
