@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("Reader highlights")
@MainActor
struct ReaderHighlightTests {
    // MARK: Internal

    @Test("addHighlight persists a colored page-anchored record")
    func addHighlightPersistsRecord() async throws {
        let (model, attachment) = try await makeModelWithRealPDF()

        model.reader.open(attachment)
        let selection = try selection(text: "a memorable passage", attachment: attachment, pageNumber: 7)
        model.reader.addHighlight(
            selection: selection,
            color: .green
        )
        try await waitUntil { model.reader.annotations.count == 1 }

        let highlight = try #require(model.reader.annotations.first)
        #expect(highlight.kind == .highlight)
        #expect(highlight.compatibilityAnnotation().color == .green)
        #expect(highlight.location == .page(7))
        #expect(highlight.text == "a memorable passage")
        #expect(highlight.rects.count == 1)
        #expect(highlight.sortIndex.contains("|") == true)
        #expect(model.statusMessage == "Added highlight")
    }

    @Test("underlines persist with their own kind and status")
    func addUnderlinePersistsRecord() async throws {
        let (model, attachment) = try await makeModelWithRealPDF()

        model.reader.open(attachment)
        let selection = try selection(text: "an argument to revisit", attachment: attachment, pageNumber: 2)
        model.reader.addHighlight(
            selection: selection,
            color: .blue,
            kind: .underline
        )
        try await waitUntil { model.reader.annotations.count == 1 }

        let underline = try #require(model.reader.annotations.first)
        #expect(underline.kind == .underline)
        #expect(model.statusMessage == "Added underline")
    }

    @Test("highlighting without an open document reports status")
    func highlightWithoutDocumentReportsStatus() throws {
        let model = makeAppModel()
        let anchor = try #require(PDFAnnotationAnchor.note(
            for: fixtureAttachment(),
            pageNumber: 1
        ))
        model.reader.addHighlight(
            selection: PDFSelectionInfo(text: "text", anchor: anchor),
            color: .yellow
        )
        #expect(model.statusMessage == "Open a document first")

        model.reader.reportMissingSelection()
        #expect(model.statusMessage == "Select text to highlight")
    }

    // MARK: Private

    private func makeModelWithRealPDF() async throws -> (AppModel, LocalAttachment) {
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
        return try (model, #require(model.importer.selectedItemAttachments.first))
    }

    private func selection(
        text: String,
        attachment: LocalAttachment,
        pageNumber: Int
    ) throws -> PDFSelectionInfo {
        try PDFSelectionInfo(
            text: text,
            anchor: #require(PDFAnnotationAnchor.note(for: attachment, pageNumber: pageNumber))
        )
    }

    private func fixtureAttachment() -> LocalAttachment {
        LocalAttachment(
            itemID: UUID(),
            fileName: "efl-drama-paper.pdf",
            objectKey: "TESTPDF1",
            localURL: realDocumentFixture("efl-drama-paper.pdf"),
            contentType: "application/pdf",
            size: 1,
            createdAt: .now
        )
    }
}
