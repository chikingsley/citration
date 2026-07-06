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
        await model.relationships.refresh()
        model.selectItem(id: source.id)

        model.relationships.targetID = target.id
        model.relationships.kind = .series
        model.relationships.noteDraft = "  Sequel paper  "
        model.relationships.addToSelectedItem()
        try await waitUntil { model.relationships.selectedItemRelationships.count == 1 }

        let relationship = try #require(model.relationships.selectedItemRelationships.first)
        #expect(relationship.sourceItemID == source.id)
        #expect(relationship.targetItemID == target.id)
        #expect(relationship.kind == .series)
        #expect(relationship.note == "Sequel paper")
        #expect(model.relationships.noteDraft.isEmpty)
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
        model.relationships.targetID = target.id
        model.relationships.addToSelectedItem()
        try await waitUntil { model.relationships.selectedItemRelationships.count == 1 }
        let relationship = try #require(model.relationships.selectedItemRelationships.first)

        model.relationships.remove(relationship)
        try await waitUntil { model.relationships.selectedItemRelationships.isEmpty }

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
        model.relationships.targetID = target.id
        model.relationships.addToSelectedItem()
        try await waitUntil { model.relationships.selectedItemRelationships.count == 1 }

        model.removeSelectedItem()
        try await waitUntil { model.items.map(\.id) == [target.id] }

        #expect(try await model.relationships.store.listRelationships(itemID: source.id).isEmpty)
        #expect(try await model.relationships.store.listRelationships(itemID: target.id).isEmpty)
    }
}
