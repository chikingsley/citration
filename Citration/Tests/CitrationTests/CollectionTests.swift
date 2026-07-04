import Testing
import Foundation
@testable import Citration
import CitrationCore

@Suite("Collections")
@MainActor
struct CollectionTests {
    @Test("createCollection updates model state")
    func createCollectionUpdatesModelState() async throws {
        let model = makeModel(initialItems: [])
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
        let model = makeModel(initialItems: [item])
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
        let model = makeModel(initialItems: [], attachmentStore: attachmentStore)
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

private extension CollectionTests {
    func makeModel(
        initialItems: [BCItem],
        attachmentStore: LocalAttachmentStore? = nil
    ) -> AppModel {
        AppModel(
            store: InMemoryItemStore(initialItems: initialItems),
            metadataRegistry: MetadataProviderRegistry(providers: [NoopMetadataProvider()]),
            citationFormatter: StubCitationFormatter(),
            storageConnectors: [],
            pdfDOIExtractor: NullPDFDOIExtractor(),
            attachmentStore: attachmentStore,
            annotationStore: makeAnnotationStore(),
            collectionStore: makeCollectionStore(),
            noteStore: makeNoteStore(),
            relationshipStore: makeRelationshipStore()
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
                .appendingPathComponent("citration-collection-annotations")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeCollectionStore() -> LocalCollectionStore? {
        try? LocalCollectionStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-collection-tests")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeNoteStore() -> LocalNoteStore? {
        try? LocalNoteStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-collection-notes")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeRelationshipStore() -> LocalRelationshipStore? {
        try? LocalRelationshipStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-collection-relationships")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-collection-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeFile(named fileName: String, contents: Data, in directory: URL) throws -> URL {
        let fileURL = directory.appendingPathComponent(fileName)
        try contents.write(to: fileURL)
        return fileURL
    }
}
