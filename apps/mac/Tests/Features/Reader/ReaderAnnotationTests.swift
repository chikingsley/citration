@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - ReaderAnnotationTests

@Suite("Reader Annotations")
@MainActor
struct ReaderAnnotationTests {
    @Test("addReaderNote persists note for active attachment")
    func addReaderNotePersistsNoteForActiveAttachment() async throws {
        let item = BCItem(title: "Paper")
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)
        model.importer.importAttachments(
            urls: [realDocumentFixture("efl-drama-paper.pdf")],
            mode: .attachToSelectedItem
        )
        try await waitUntil {
            model.importer.selectedItemAttachments.count == 1 && !model.importer.isImporting
        }
        let attachment = try #require(model.importer.selectedItemAttachments.first)

        model.reader.open(attachment)
        model.reader.noteDraft = "  Remember this argument  "
        model.reader.addNote()
        try await waitUntil { model.reader.annotations.count == 1 }

        #expect(model.reader.noteDraft.isEmpty)
        #expect(model.reader.annotations.first?.comment == "Remember this argument")
        #expect(model.reader.annotations.first?.syncState == .dirty)
        #expect(model.reader.annotations.first?.rects.count == 1)
        #expect(model.reader.annotations.first?.sortIndex.contains("|") == true)
        #expect(model.statusMessage == "Added note")
    }

    @Test("addReaderNote rejects empty note")
    func addReaderNoteRejectsEmptyNote() {
        let model = makeAppModel()

        model.reader.noteDraft = "   "
        model.reader.addNote()

        #expect(model.statusMessage == "Enter a note first")
        #expect(model.reader.annotations.isEmpty)
    }

    @Test("editing an annotation preserves its synchronized geometry")
    func editingAnnotationPreservesSynchronizedGeometry() async throws {
        let item = BCItem(title: "Paper")
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)
        model.importer.importAttachments(
            urls: [realDocumentFixture("efl-drama-paper.pdf")],
            mode: .attachToSelectedItem
        )
        try await waitUntil {
            model.importer.selectedItemAttachments.count == 1 && !model.importer.isImporting
        }
        let attachment = try #require(model.importer.selectedItemAttachments.first)
        model.reader.open(attachment)
        model.reader.noteDraft = "Original note"
        model.reader.addNote()
        try await waitUntil { model.reader.annotations.count == 1 }
        let original = try #require(model.reader.annotations.first)

        model.reader.updateAnnotation(
            original,
            kind: .note,
            color: .blue,
            comment: "Revised note",
            tags: [ZoteroProjectedTag(position: 0, value: "important", type: nil)]
        )
        try await waitUntil { model.reader.annotations.first?.comment == "Revised note" }
        let revised = try #require(model.reader.annotations.first)

        #expect(revised.positionJSON == original.positionJSON)
        #expect(revised.sortIndex == original.sortIndex)
        #expect(revised.identity == original.identity)
        #expect(revised.compatibilityAnnotation().color == .blue)
        #expect(revised.tags.map(\.value) == ["important"])
        #expect(model.statusMessage == "Updated annotation")
    }
}
