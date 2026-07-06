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

        model.notes.draft = "  Check related work  "
        model.notes.addToSelectedItem()
        try await waitUntil { model.notes.selectedItemNotes.count == 1 }

        #expect(model.notes.draft.isEmpty)
        #expect(model.notes.selectedItemNotes.first?.text == "Check related work")
        #expect(model.statusMessage == "Added note")
    }

    @Test("addNoteToSelectedItem rejects empty note")
    func addNoteToSelectedItemRejectsEmptyNote() async {
        let item = BCItem(title: "Paper")
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.notes.draft = "   "
        model.notes.addToSelectedItem()

        #expect(model.statusMessage == "Enter a note first")
        #expect(model.notes.selectedItemNotes.isEmpty)
    }

    @Test("removeSelectedItem removes item notes")
    func removeSelectedItemRemovesItemNotes() async throws {
        let item = BCItem(title: "Paper")
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)
        model.notes.draft = "Delete with item"
        model.notes.addToSelectedItem()
        try await waitUntil { model.notes.selectedItemNotes.count == 1 }

        model.removeSelectedItem()
        try await waitUntil { model.items.isEmpty }

        #expect(try await model.notes.store.listNotes(itemID: item.id).isEmpty)
    }
}
