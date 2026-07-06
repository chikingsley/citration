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
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let annotationStore = try LocalAnnotationStore(
            storeURL: tempDirectory.appendingPathComponent("annotations.json")
        )
        let attachment = makeAttachment(
            itemID: UUID(),
            fileName: "reader.pdf",
            contentType: "application/pdf"
        )
        let model = makeAppModel(annotationStore: annotationStore)

        model.reader.open(attachment)
        model.reader.noteDraft = "  Remember this argument  "
        model.reader.addNote()
        try await waitUntil { model.reader.annotations.count == 1 }

        #expect(model.reader.noteDraft.isEmpty)
        #expect(model.reader.annotations.first?.note == "Remember this argument")
        #expect(model.statusMessage == "Added note")
    }

    @Test("addReaderNote rejects empty note")
    func addReaderNoteRejectsEmptyNote() throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let annotationStore = try LocalAnnotationStore(
            storeURL: tempDirectory.appendingPathComponent("annotations.json")
        )
        let model = makeAppModel(annotationStore: annotationStore)

        model.reader.noteDraft = "   "
        model.reader.addNote()

        #expect(model.statusMessage == "Enter a note first")
        #expect(model.reader.annotations.isEmpty)
    }
}
