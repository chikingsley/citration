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

        model.openReader(for: attachment)
        model.readerNoteDraft = "  Remember this argument  "
        model.addReaderNote()
        try await waitUntil { model.activeReaderAnnotations.count == 1 }

        #expect(model.readerNoteDraft.isEmpty)
        #expect(model.activeReaderAnnotations.first?.note == "Remember this argument")
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

        model.readerNoteDraft = "   "
        model.addReaderNote()

        #expect(model.statusMessage == "Enter a note first")
        #expect(model.activeReaderAnnotations.isEmpty)
    }
}
