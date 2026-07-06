@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("Reader highlights")
@MainActor
struct ReaderHighlightTests {
    @Test("addHighlight persists a colored page-anchored record")
    func addHighlightPersistsRecord() async throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let annotationStore = try LocalAnnotationStore(
            storeURL: tempDirectory.appendingPathComponent("annotations.json")
        )
        let attachment = makeAttachment(
            itemID: UUID(),
            fileName: "paper.pdf",
            contentType: "application/pdf"
        )
        let model = makeAppModel(annotationStore: annotationStore)

        model.reader.open(attachment)
        model.reader.addHighlight(
            text: "a memorable passage",
            pageNumber: 7,
            color: .green
        )
        try await waitUntil { model.reader.annotations.count == 1 }

        let highlight = try #require(model.reader.annotations.first)
        #expect(highlight.kind == .highlight)
        #expect(highlight.color == .green)
        #expect(highlight.location == .page(7))
        #expect(highlight.selectedText == "a memorable passage")
        #expect(model.statusMessage == "Added highlight")
    }

    @Test("underlines persist with their own kind and status")
    func addUnderlinePersistsRecord() async throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let annotationStore = try LocalAnnotationStore(
            storeURL: tempDirectory.appendingPathComponent("annotations.json")
        )
        let attachment = makeAttachment(
            itemID: UUID(),
            fileName: "paper.pdf",
            contentType: "application/pdf"
        )
        let model = makeAppModel(annotationStore: annotationStore)

        model.reader.open(attachment)
        model.reader.addHighlight(
            text: "an argument to revisit",
            pageNumber: 2,
            color: .blue,
            kind: .underline
        )
        try await waitUntil { model.reader.annotations.count == 1 }

        let underline = try #require(model.reader.annotations.first)
        #expect(underline.kind == .underline)
        #expect(model.statusMessage == "Added underline")
    }

    @Test("highlighting without an open document reports status")
    func highlightWithoutDocumentReportsStatus() {
        let model = makeAppModel()
        model.reader.addHighlight(text: "text", pageNumber: 1, color: .yellow)
        #expect(model.statusMessage == "Open a document first")

        model.reader.reportMissingSelection()
        #expect(model.statusMessage == "Select text to highlight")
    }
}
