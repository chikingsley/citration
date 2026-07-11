@testable import Citration
import CitrationCore
import Foundation
import PDFKit
import Testing

@Suite("Portable annotation export")
@MainActor
struct AnnotationExportTests {
    // MARK: Internal

    @Test("sidecar and annotated PDF copy preserve the canonical real file")
    func exportsWithoutModifyingCanonicalAttachment() async throws {
        let item = BCItem(title: "Exported Paper")
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
        let canonicalBefore = try Data(contentsOf: attachment.localURL)
        model.reader.open(attachment)
        let anchor = try #require(PDFAnnotationAnchor.note(for: attachment, pageNumber: 2))
        model.reader.addHighlight(
            selection: PDFSelectionInfo(text: "portable passage", anchor: anchor),
            color: .blue
        )
        try await waitUntil { model.reader.annotations.count == 1 }

        let sidecar = try await AnnotationExportService.sidecarData(
            attachment: attachment,
            annotations: model.reader.annotations
        )
        let sidecarObject = try #require(
            JSONSerialization.jsonObject(with: sidecar) as? [String: Any]
        )
        let source = try #require(sidecarObject["source"] as? [String: Any])
        let records = try #require(sidecarObject["annotations"] as? [[String: Any]])
        #expect(sidecarObject["schemaVersion"] as? Int == 1)
        #expect(source["objectKey"] as? String == attachment.objectKey)
        #expect((source["sha256"] as? String)?.count == 64)
        #expect(records.first?["text"] as? String == "portable passage")
        #expect((records.first?["position"] as? [String: Any])?["pageIndex"] as? Int == 1)

        let canonicalDocument = try #require(PDFDocument(data: canonicalBefore))
        let annotatedData = try AnnotationExportService.annotatedPDFData(
            attachment: attachment,
            annotations: model.reader.annotations
        )
        let annotatedDocument = try #require(PDFDocument(data: annotatedData))
        #expect(annotationCount(in: annotatedDocument) > annotationCount(in: canonicalDocument))
        #expect(
            (0 ..< annotatedDocument.pageCount)
                .compactMap { annotatedDocument.page(at: $0) }
                .flatMap(\.annotations)
                .contains { $0.contents == "portable passage" }
        )
        #expect(try Data(contentsOf: attachment.localURL) == canonicalBefore)
    }

    // MARK: Private

    private func annotationCount(in document: PDFDocument) -> Int {
        (0 ..< document.pageCount).reduce(into: 0) { count, pageIndex in
            count += document.page(at: pageIndex)?.annotations.count ?? 0
        }
    }
}
