@testable import Citration
import CitrationCore
import PDFKit
import Testing

@Suite("Reader ink")
@MainActor
struct ReaderInkTests {
    // MARK: Internal

    @Test("a real PDF page stroke persists as compatible Zotero ink")
    func realPDFStrokePersistsAsZoteroInk() async throws {
        let (model, attachment) = try await makeModelWithRealPDF()
        let document = try #require(PDFDocument(url: attachment.localURL))
        let page = try #require(document.page(at: 0))
        let points = [
            CGPoint(x: 72, y: 700),
            CGPoint(x: 84, y: 706),
            CGPoint(x: 98, y: 702),
        ]
        let anchor = try #require(PDFAnnotationAnchor.ink(
            page: page,
            pageIndex: 0,
            points: points,
            width: 1.5
        ))

        model.reader.open(attachment)
        model.reader.beginInk(color: .pink)
        model.reader.addInk(PDFInkStrokeInfo(anchor: anchor))
        try await waitUntil { model.reader.annotations.count == 1 }

        let ink = try #require(model.reader.annotations.first)
        #expect(ink.kind == .ink)
        #expect(ink.inkWidth == 1.5)
        #expect(ink.inkPaths == [points.map { ZoteroAnnotationPoint(x: $0.x, y: $0.y) }])
        #expect(ink.compatibilityAnnotation().color == .pink)
        #expect(ink.syncState == .dirty)
        #expect(model.statusMessage == "Added ink stroke")
        let libraryID = try #require(model.observedLibraryID)
        let object = try #require(try model.database.fetchObject(
            libraryID: libraryID,
            kind: .item,
            key: ink.identity.objectKey
        ))
        #expect(object.current.objectValue?["data"]?.objectValue?["annotationText"] == nil)
    }

    @Test("drawing mode is explicit and reversible")
    func drawingModeIsExplicitAndReversible() async throws {
        let (model, attachment) = try await makeModelWithRealPDF()
        model.reader.open(attachment)

        model.reader.beginInk(color: .blue)
        #expect(model.reader.isInkMode)
        #expect(model.reader.inkColor == .blue)

        model.reader.endInk()
        #expect(!model.reader.isInkMode)
        #expect(model.statusMessage == "Stopped drawing")
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
}
