@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - ItemRelationshipTests

@Suite("Item Relationships")
@MainActor
struct ItemRelationshipTests {
    @Test("addRelationshipToSelectedItem persists link and recommendation")
    func addRelationshipToSelectedItemPersistsLinkAndRecommendation() async throws {
        let source = BCItem(title: "Source")
        let target = BCItem(title: "Target")
        let model = makeModel(initialItems: [source, target])
        await model.refreshItems()
        await model.refreshRelationships()
        model.selectItem(id: source.id)

        model.relatedItemTargetID = target.id
        model.relatedItemKind = .series
        model.relatedItemNoteDraft = "  Sequel paper  "
        model.addRelationshipToSelectedItem()
        try await waitUntil { model.selectedItemRelationships.count == 1 }

        let relationship = try #require(model.selectedItemRelationships.first)
        #expect(relationship.sourceItemID == source.id)
        #expect(relationship.targetItemID == target.id)
        #expect(relationship.kind == .series)
        #expect(relationship.note == "Sequel paper")
        #expect(model.relatedItemNoteDraft.isEmpty)
        #expect(model.statusMessage == "Linked related item")
        #expect(model.selectedItemRecommendations.map(\.candidateItemID) == [target.id])
        #expect(model.selectedItemRecommendations.first?.reasons == [.userLinked(.series)])
    }

    @Test("removeRelationship removes selected link")
    func removeRelationshipRemovesSelectedLink() async throws {
        let source = BCItem(title: "Source")
        let target = BCItem(title: "Target")
        let model = makeModel(initialItems: [source, target])
        await model.refreshItems()
        model.selectItem(id: source.id)
        model.relatedItemTargetID = target.id
        model.addRelationshipToSelectedItem()
        try await waitUntil { model.selectedItemRelationships.count == 1 }
        let relationship = try #require(model.selectedItemRelationships.first)

        model.removeRelationship(relationship)
        try await waitUntil { model.selectedItemRelationships.isEmpty }

        #expect(model.selectedItemRecommendations.isEmpty)
        #expect(model.statusMessage == "Removed related item")
    }

    @Test("removeSelectedItem removes relationships touching item")
    func removeSelectedItemRemovesRelationshipsTouchingItem() async throws {
        let source = BCItem(title: "Source")
        let target = BCItem(title: "Target")
        let model = makeModel(initialItems: [source, target])
        await model.refreshItems()
        model.selectItem(id: source.id)
        model.relatedItemTargetID = target.id
        model.addRelationshipToSelectedItem()
        try await waitUntil { model.selectedItemRelationships.count == 1 }

        model.removeSelectedItem()
        try await waitUntil { model.items.map(\.id) == [target.id] }

        #expect(try await model.relationshipStore.listRelationships(itemID: source.id).isEmpty)
        #expect(try await model.relationshipStore.listRelationships(itemID: target.id).isEmpty)
    }
}

private extension ItemRelationshipTests {
    func makeModel(initialItems: [BCItem]) -> AppModel {
        AppModel(
            store: InMemoryItemStore(initialItems: initialItems),
            metadataRegistry: MetadataProviderRegistry(providers: [NoopMetadataProvider()]),
            citationFormatter: StubCitationFormatter(),
            storageConnectors: [],
            pdfDOIExtractor: NullPDFDOIExtractor(),
            attachmentStore: nil,
            annotationStore: makeAnnotationStore(),
            collectionStore: makeCollectionStore(),
            noteStore: makeNoteStore(),
            relationshipStore: makeRelationshipStore(),
            readerProgressStore: makeReaderProgressStore()
        )
    }

    func waitUntil(
        timeout: TimeInterval = 2.0,
        pollInterval: UInt64 = 10_000_000,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        Issue.record("Timed out waiting for condition")
    }

    func makeAnnotationStore() -> LocalAnnotationStore? {
        try? LocalAnnotationStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-item-relationship-annotations")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeCollectionStore() -> LocalCollectionStore? {
        try? LocalCollectionStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-item-relationship-collections")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeNoteStore() -> LocalNoteStore? {
        try? LocalNoteStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-item-relationship-notes")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeRelationshipStore() -> LocalRelationshipStore? {
        try? LocalRelationshipStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-item-relationship-relationships")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeReaderProgressStore() -> LocalReaderProgressStore? {
        try? LocalReaderProgressStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-item-relationship-reader-progress")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }
}
