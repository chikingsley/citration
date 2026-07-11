@testable import Citration
import CitrationCore
import PDFKit
import Testing

@Suite("Zotero PDF annotation rendering")
struct ZoteroPDFAnnotationRendererTests {
    // MARK: Internal

    @Test("stored Zotero rectangles render without text re-anchoring")
    func storedRectanglesRenderExactly() throws {
        let document = try #require(PDFDocument(url: realDocumentFixture("efl-drama-paper.pdf")))
        let annotation = synchronizedAnnotation(
            type: "highlight",
            text: "This deliberately does not need to occur in the PDF.",
            comment: "Exact geometry wins.",
            positionJSON: "{\"pageIndex\":0,\"rects\":[[72.5,144.25,212.75,158.5]]}"
        )

        let rendered = ZoteroPDFAnnotationRenderer.render(annotation, in: document)

        let marking = try #require(rendered.first)
        #expect(rendered.count == 1)
        #expect(marking.type == "Highlight")
        #expect(marking.bounds.origin.x == 72.5)
        #expect(marking.bounds.origin.y == 144.25)
        #expect(marking.bounds.width == 140.25)
        #expect(marking.bounds.height == 14.25)
    }

    @Test("stored Zotero note rectangles render comments")
    func storedNoteRectanglesRenderComments() throws {
        let document = try #require(PDFDocument(url: realDocumentFixture("efl-drama-paper.pdf")))
        let annotation = synchronizedAnnotation(
            type: "note",
            text: "",
            comment: "A synchronized margin note",
            positionJSON: "{\"pageIndex\":0,\"rects\":[[300,500,322,522]]}"
        )

        let rendered = ZoteroPDFAnnotationRenderer.render(annotation, in: document)

        let note = try #require(rendered.first)
        #expect(note.type == "Text")
        #expect(note.contents == "A synchronized margin note")
        #expect(note.bounds.width == 22)
        #expect(note.bounds.height == 22)
    }

    @Test("cross-page Zotero rectangles render on both exact pages")
    func crossPageRectanglesRenderExactly() throws {
        let document = try #require(PDFDocument(url: realDocumentFixture("efl-drama-paper.pdf")))
        let annotation = synchronizedAnnotation(
            type: "underline",
            text: "A cross-page selection",
            comment: "",
            positionJSON: """
            {"pageIndex":0,"rects":[[72,100,180,114]],"nextPageRects":[[72,700,140,714]]}
            """
        )

        let rendered = ZoteroPDFAnnotationRenderer.render(annotation, in: document)

        #expect(rendered.count == 2)
        #expect(rendered[0].page == document.page(at: 0))
        #expect(rendered[1].page == document.page(at: 1))
        #expect(rendered[1].bounds.origin.y == 700)
    }

    @Test("stored Zotero ink paths render with exact points and width")
    func storedInkPathsRenderExactly() throws {
        let document = try #require(PDFDocument(url: realDocumentFixture("efl-drama-paper.pdf")))
        let annotation = synchronizedAnnotation(
            type: "ink",
            text: "",
            comment: "",
            positionJSON: """
            {"pageIndex":0,"paths":[[72,100,80,108,92,104],[120,130,121,132]],"width":2}
            """
        )

        let rendered = ZoteroPDFAnnotationRenderer.render(annotation, in: document)

        let ink = try #require(rendered.first)
        #expect(rendered.count == 1)
        #expect(ink.type == "Ink")
        #expect(ink.paths?.count == 2)
        #expect(ink.border?.lineWidth == 2)
        #expect(ink.bounds.minX == 70)
        #expect(ink.bounds.minY == 98)
        #expect(ink.bounds.maxX == 123)
        #expect(ink.bounds.maxY == 134)
    }

    @Test("a real PDFKit selection produces Zotero position geometry and sort metadata")
    @MainActor
    func realSelectionProducesZoteroMetadata() throws {
        let document = try #require(PDFDocument(url: realDocumentFixture("efl-drama-paper.pdf")))
        let token = try #require(document.string?.split(whereSeparator: { !$0.isLetter }).first)
        let selection = try #require(document.findString(String(token), withOptions: []).first)
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.setCurrentSelection(selection, animate: false)
        let proxy = PDFViewProxy()
        proxy.pdfView = pdfView

        let info = try #require(proxy.selectionInfo())
        let positionData = try #require(info.anchor.positionJSON.data(using: .utf8))
        let position = try #require(try ZoteroJSON.decode(positionData).objectValue)

        #expect(!info.text.isEmpty)
        #expect(info.anchor.sortIndex.split(separator: "|").map(\.count) == [5, 6, 5])
        #expect(position["pageIndex"]?.integerValue == Int64(info.anchor.pageIndex))
        #expect(position["rects"]?.arrayValue?.isEmpty == false)
    }

    // MARK: Private

    private func synchronizedAnnotation(
        type: String,
        text: String,
        comment: String,
        positionJSON: String
    ) -> SynchronizedLibraryAnnotation {
        let libraryID: Int64 = 42
        return SynchronizedLibraryAnnotation(
            identity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: "ANNOT001",
                appUUID: UUID()
            ),
            parentAttachmentIdentity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: "ATTACH01",
                appUUID: UUID()
            ),
            bibliographicItemIdentity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: "BIBITEM1",
                appUUID: UUID()
            ),
            version: 12,
            syncState: .synced,
            type: type,
            color: "#ffd400",
            pageLabel: "1",
            sortIndex: "00000|000144|00072",
            text: text,
            comment: comment,
            positionJSON: positionJSON,
            tags: [],
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
}
