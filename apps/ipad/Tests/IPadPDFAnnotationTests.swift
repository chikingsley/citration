import CitrationCore
@testable import CitrationPad
import Foundation
import PDFKit
import Testing
import UIKit

@Suite("iPad PDF annotations")
struct IPadPDFAnnotationTests {
    // MARK: Internal

    @Test("PDF annotations persist and render through the production stores")
    func pencilGeometryPersistsAndRenders() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-ipad-pencil-tests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pdfURL = directory.appending(path: "pencil.pdf")
        try Self.pdfData().write(to: pdfURL)
        let document = try #require(PDFDocument(url: pdfURL))
        let page = try #require(document.page(at: 0))
        let paths = [
            [CGPoint(x: 72, y: 180), CGPoint(x: 96, y: 202), CGPoint(x: 130, y: 190)]
        ]
        let anchor = try #require(IPadPDFAnnotationAnchor.ink(
            page: page,
            pageIndex: 0,
            paths: paths,
            width: 2
        ))
        let selectionAnchor = try #require(IPadPDFAnnotationAnchor.selection(
            page: page,
            pageIndex: 0,
            rects: [CGRect(x: 72, y: 110, width: 180, height: 24)]
        ))

        let context = try await Self.makeContext(directory: directory, pdfURL: pdfURL)
        await Self.createAnnotations(
            model: context.model,
            item: context.synchronizedItem,
            record: context.record,
            inkAnchor: anchor,
            selectionAnchor: selectionAnchor
        )

        let stored = try await context.store.listSynchronizedAnnotations(
            itemID: context.item.id,
            attachmentKey: context.attachment.objectKey
        )
        let storedInk = try #require(stored.first { $0.kind == .ink })
        #expect(stored.count == 4)
        #expect(storedInk.inkPaths == paths.map { path in
            path.map { ZoteroAnnotationPoint(x: $0.x, y: $0.y) }
        })
        #expect(storedInk.inkWidth == 2)

        let reopened = try #require(PDFDocument(url: context.attachment.localURL))
        let rendered = stored.flatMap { IPadPDFAnnotationRenderer.render($0, in: reopened) }
        #expect(rendered.count == 4)
        #expect(Set(rendered.compactMap(\.type)) == Set(["Highlight", "Ink", "Text", "Underline"]))
        #expect(try context.database.integrityCheck() == "ok")
    }

    // MARK: Private

    private struct TestContext {
        let database: CitrationDatabase
        let store: CitrationLibraryStore
        let item: BCItem
        let attachment: LibraryAttachment
        let synchronizedItem: SynchronizedLibraryItem
        let record: ZoteroAttachmentCacheRecord
        let model: IPadLibraryModel
    }

    @MainActor
    private static func makeContext(
        directory: URL,
        pdfURL: URL
    ) async throws -> TestContext {
        let database = try CitrationDatabase(at: directory.appending(path: "library.sqlite"))
        let item = BCItem(title: "Pencil Evidence")
        let attachments = directory.appending(path: "attachments", directoryHint: .isDirectory)
        let store = try CitrationLibraryStore(database: database, attachmentsDirectory: attachments, initialItems: [item])
        let attachment = try await store.importFile(from: pdfURL, for: item)
        let synchronizedItem = try #require(await store.listLibraryItems().first)
        let libraryID = await store.selectedLibraryID()
        let storedRecord = try database.attachmentCacheRecord(
            libraryID: libraryID,
            itemKey: attachment.objectKey
        )
        let record = try #require(storedRecord)
        let model = IPadLibraryModel(
            database: database,
            store: store,
            connectionManager: ZoteroConnectionManager(
                database: database,
                credentialStore: FileZoteroCredentialStore(fileURL: directory.appending(path: "device-key")),
                attachmentsDirectory: attachments
            )
        )
        return TestContext(
            database: database,
            store: store,
            item: item,
            attachment: attachment,
            synchronizedItem: synchronizedItem,
            record: record,
            model: model
        )
    }

    private static func createAnnotations(
        model: IPadLibraryModel,
        item: SynchronizedLibraryItem,
        record: ZoteroAttachmentCacheRecord,
        inkAnchor: IPadPDFAnnotationAnchor,
        selectionAnchor: IPadPDFAnnotationAnchor
    ) async {
        for (kind, annotationAnchor, comment) in [
            (AnnotationKind.ink, inkAnchor, ""),
            (.highlight, selectionAnchor, ""),
            (.underline, selectionAnchor, ""),
            (.note, selectionAnchor, "Reader note"),
        ] {
            await model.createPDFAnnotation(
                item: item,
                record: record,
                anchor: annotationAnchor,
                kind: kind,
                color: .blue,
                text: kind == .ink ? "" : "Selected text",
                comment: comment
            )
        }
    }

    private static func pdfData() -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            let text = "A real PDF page for Apple Pencil annotation evidence."
            text.draw(
                at: CGPoint(x: 72, y: 120),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
            )
        }
    }
}
