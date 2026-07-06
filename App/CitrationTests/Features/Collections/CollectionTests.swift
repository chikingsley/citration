@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - CollectionTests

@Suite("Collections")
@MainActor
struct CollectionTests {
    @Test("createCollection updates model state")
    func createCollectionUpdatesModelState() async throws {
        let model = makeAppModel(initialItems: [])
        await model.refreshCollections()

        model.createCollection(named: "  Reading   Queue ")
        try await waitUntil { model.collections.count == 1 }

        #expect(model.collections.first?.name == "Reading Queue")
        #expect(model.selectedCollectionID == model.collections.first?.id)
        #expect(model.statusMessage == "Created collection")
    }

    @Test("setSelectedItem toggles collection membership")
    func setSelectedItemTogglesMembership() async throws {
        let item = BCItem(title: "Paper")
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        await model.refreshCollections()
        model.selectItem(id: item.id)
        model.createCollection(named: "AI")
        try await waitUntil { model.collections.count == 1 }
        let collection = try #require(model.collections.first)

        model.setSelectedItem(item, memberOf: collection, isMember: true)
        try await waitUntil { model.selectedItemCollectionIDs == [collection.id] }
        #expect(model.selectedCollectionItems.map(\.id) == [item.id])

        model.setSelectedItem(item, memberOf: collection, isMember: false)
        try await waitUntil { model.selectedItemCollectionIDs.isEmpty }
    }

    @Test("import adds new item to selected collection")
    func importAddsNewItemToSelectedCollection() async throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let sourceFile = try makeFile(named: "collection.pdf", contents: Data("dummy".utf8), in: tempDirectory)
        let attachmentStore = try LocalAttachmentStore(
            baseDirectory: tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        )
        let model = makeAppModel(initialItems: [], attachmentStore: attachmentStore)
        await model.refreshItems()
        await model.refreshCollections()
        model.createCollection(named: "Inbox")
        try await waitUntil { model.collections.count == 1 }
        let collectionID = try #require(model.collections.first?.id)
        model.selectCollection(id: collectionID)

        model.importAttachments(urls: [sourceFile], mode: AppModel.AttachmentImportMode.createNewItemPerFile)
        try await waitUntil(timeout: 3.0) { model.items.count == 1 && model.collectionMemberships.count == 1 }

        #expect(model.collectionMemberships.first?.collectionID == collectionID)
        #expect(model.collectionMemberships.first?.itemID == model.items.first?.id)
        #expect(model.selectedCollectionItems.map(\.id) == model.items.map(\.id))
    }
}
