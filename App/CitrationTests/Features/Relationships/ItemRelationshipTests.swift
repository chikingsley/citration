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
        let model = makeAppModel(initialItems: [source, target])
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
        let model = makeAppModel(initialItems: [source, target])
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
        let model = makeAppModel(initialItems: [source, target])
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
