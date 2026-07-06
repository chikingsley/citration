@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - ItemNoteTests

@Suite("Item Notes")
@MainActor
struct ItemNoteTests {
    @Test("addNoteToSelectedItem persists trimmed note")
    func addNoteToSelectedItemPersistsTrimmedNote() async throws {
        let item = BCItem(title: "Paper")
        let model = makeAppModel(initialItems: [item])
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
        let model = makeAppModel(initialItems: [item])
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
        let model = makeAppModel(initialItems: [item])
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
