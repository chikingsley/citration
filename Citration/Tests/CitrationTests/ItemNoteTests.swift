import Testing
import Foundation
@testable import Citration
import CitrationCore

@Suite("Item Notes")
@MainActor
struct ItemNoteTests {
    @Test("addNoteToSelectedItem persists trimmed note")
    func addNoteToSelectedItemPersistsTrimmedNote() async throws {
        let item = BCItem(title: "Paper")
        let model = makeModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.itemNoteDraft = "  Check related work  "
        model.addNoteToSelectedItem()
        try await waitUntil { model.selectedItemNotes.count == 1 }

        #expect(model.itemNoteDraft.isEmpty)
        #expect(model.selectedItemNotes.first?.text == "Check related work")
        #expect(model.statusMessage == "Added note")
    }

    @Test("addNoteToSelectedItem rejects empty note")
    func addNoteToSelectedItemRejectsEmptyNote() async {
        let item = BCItem(title: "Paper")
        let model = makeModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.itemNoteDraft = "   "
        model.addNoteToSelectedItem()

        #expect(model.statusMessage == "Enter a note first")
        #expect(model.selectedItemNotes.isEmpty)
    }

    @Test("removeSelectedItem removes item notes")
    func removeSelectedItemRemovesItemNotes() async throws {
        let item = BCItem(title: "Paper")
        let model = makeModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)
        model.itemNoteDraft = "Delete with item"
        model.addNoteToSelectedItem()
        try await waitUntil { model.selectedItemNotes.count == 1 }

        model.removeSelectedItem()
        try await waitUntil { model.items.isEmpty }

        #expect(try await model.noteStore.listNotes(itemID: item.id).isEmpty)
    }
}

private extension ItemNoteTests {
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
            noteStore: makeNoteStore()
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
                .appendingPathComponent("citration-item-note-annotations")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeCollectionStore() -> LocalCollectionStore? {
        try? LocalCollectionStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-item-note-collections")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeNoteStore() -> LocalNoteStore? {
        try? LocalNoteStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-item-note-notes")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }
}
