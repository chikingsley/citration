@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - TaggingTests

@Suite("Item Tagging")
@MainActor
struct TaggingTests {
    @Test("addTagToSelectedItem persists normalized tag")
    func addTagToSelectedItemPersistsNormalizedTag() async throws {
        let item = BCItem(title: "Tagged", tags: ["vision"])
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.tagDraft = "  Machine   Learning  "
        model.addTagToSelectedItem()
        try await waitUntil { model.selectedItem?.tags == ["vision", "Machine Learning"] }

        #expect(model.tagDraft.isEmpty)
        #expect(model.statusMessage == "Added tag")
    }

    @Test("removeTag deletes tag from selected item")
    func removeTagDeletesTag() async throws {
        let item = BCItem(title: "Tagged", tags: ["vision", "machine learning"])
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)

        let selected = try #require(model.selectedItem)
        model.removeTag("machine learning", from: selected)
        try await waitUntil { model.selectedItem?.tags == ["vision"] }

        #expect(model.statusMessage == "Removed tag")
    }

    @Test("metadata enrichment preserves existing tags")
    func metadataEnrichmentPreservesTags() async throws {
        let doi = "10.5555/tagged"
        let provider = TagMetadataProvider(
            records: [
                CanonicalMetadataRecord(
                    title: "Resolved Title",
                    creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
                    publicationYear: 1843,
                    itemType: .article,
                    identifiers: [Identifier(type: .doi, value: doi)],
                    confidence: 0.9,
                    provenance: MetadataProvenance(providerName: "stub-provider")
                )
            ],
            delayNanoseconds: 10_000_000
        )
        let item = BCItem(title: "Draft", tags: ["keep"])
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let sourceFile = try makeFile(named: "tagged.pdf", contents: Data("dummy".utf8), in: tempDirectory)
        let attachmentStore = try LocalAttachmentStore(
            baseDirectory: tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        )
        let model = makeAppModel(
            initialItems: [item],
            providers: [provider],
            pdfDOIExtractor: TagPDFDOIExtractor(doi: doi),
            attachmentStore: attachmentStore
        )
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.importAttachments(urls: [sourceFile], mode: AppModel.AttachmentImportMode.attachToSelectedItem)
        try await waitUntil(timeout: 3.0) { model.selectedItem?.doi == doi }

        #expect(model.selectedItem?.tags == ["keep"])
    }
}

// MARK: - TagMetadataProvider

private struct TagMetadataProvider: MetadataProvider {
    let name: String = "tag-metadata"
    let records: [CanonicalMetadataRecord]
    let delayNanoseconds: UInt64

    func resolve(_ request: MetadataResolutionRequest) async -> [CanonicalMetadataRecord] {
        _ = request
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return records
    }
}

// MARK: - TagPDFDOIExtractor

private struct TagPDFDOIExtractor: PDFDOIExtracting {
    let doi: String?

    func extractDOI(from pdfURL: URL) -> String? {
        _ = pdfURL
        return doi
    }
}
