@testable import Citration
import CitrationCore
import Foundation
import Testing
import WebKit

// MARK: - ItemNoteTests

@Suite("Item Notes")
@MainActor
struct ItemNoteTests {
    @Test("note HTML rendering disables active content and remote resources")
    func noteHTMLRenderingIsIsolated() {
        let noteHTML = "<p>Preserve <strong>formatting</strong><script>alert('no')</script></p>"
        let configuration = NoteHTMLView.makeConfiguration()
        let document = NoteHTMLView.document(containing: noteHTML)

        #expect(!configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(!configuration.websiteDataStore.isPersistent)
        #expect(document.contains("default-src 'none'"))
        #expect(document.contains(noteHTML))
    }

    @Test("addNoteToSelectedItem persists trimmed note")
    func addNoteToSelectedItemPersistsTrimmedNote() async throws {
        let item = BCItem(title: "Paper")
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.notes.draft = "  Check <related> & linked work  "
        model.notes.addToSelectedItem()
        try await waitUntil { model.notes.selectedItemNotes.count == 1 }

        #expect(model.notes.draft.isEmpty)
        let note = try #require(model.notes.selectedItemNotes.first)
        #expect(note.html == "<p>Check &lt;related&gt; &amp; linked work</p>")
        #expect(!note.identity.objectKey.isEmpty)
        #expect(note.parentIdentity.appUUID == item.id)
        #expect(note.version == 0)
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
