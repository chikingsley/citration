@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("AppModel import")
@MainActor
struct AppModelImportTests {
    @Test("import enriches item with normalized DOI title and creators")
    func importEnrichesItemWithNormalizedDOITitleAndCreators() async throws {
        let doi = "10.5555/abc123"
        let provider = StubMetadataProvider(
            records: [
                CanonicalMetadataRecord(
                    title: "  Real   Metadata   Title ",
                    creators: [
                        Creator(givenName: "  Grace ", familyName: " Hopper "),
                        Creator(givenName: "  Alan", familyName: "  Turing  "),
                    ],
                    publicationYear: 1952,
                    itemType: .article,
                    identifiers: [Identifier(type: .doi, value: doi)],
                    confidence: 0.9,
                    provenance: MetadataProvenance(providerName: "stub-provider")
                )
            ],
            delayNanoseconds: 10_000_000
        )

        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let sourceFile = try makeFile(named: "input.pdf", contents: Data("dummy".utf8), in: tempDirectory)
        let attachmentsDirectory = tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        let attachmentStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)

        let model = makeAppModel(
            providers: [provider],
            pdfDOIExtractor: StubPDFDOIExtractor(doi: doi),
            attachmentStore: attachmentStore
        )
        await model.refreshItems()

        model.importAttachments(urls: [sourceFile], mode: .createNewItemPerFile)
        try await waitUntil(timeout: 3.0) { model.items.count == 1 && model.items.first?.doi == doi }

        let imported = try #require(model.items.first)
        #expect(imported.title == "Real Metadata Title")
        #expect(imported.creators.first?.displayName == "Grace Hopper")
        #expect(imported.creators.count == 2)
        #expect(model.statusMessage.contains("detected 1 DOI"))
    }

    @Test("import resolves metadata in arXiv then DOI order")
    func importResolvesMetadataInArXivThenDOIOrder() async throws {
        let recorder = MetadataRequestRecorder()
        let provider = OrderedResolutionProvider(recorder: recorder)

        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let sourceFile = try makeFile(named: "order.pdf", contents: Data("dummy".utf8), in: tempDirectory)
        let attachmentsDirectory = tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        let attachmentStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)

        let extractor = StubPDFCandidateExtractor(
            candidates: PDFMetadataCandidates(
                identifiers: [
                    Identifier(type: .arxiv, value: "2401.01234"),
                    Identifier(type: .doi, value: "10.5555/fallback-doi"),
                    Identifier(type: .isbn, value: "9780306406157"),
                ],
                titleHints: ["Some Fallback Title"]
            )
        )

        let model = makeAppModel(
            providers: [provider],
            pdfDOIExtractor: extractor,
            attachmentStore: attachmentStore
        )
        await model.refreshItems()

        model.importAttachments(urls: [sourceFile], mode: .createNewItemPerFile)
        try await waitUntil(timeout: 3.0) { model.items.first?.title == "Resolved From DOI" }

        let requests = await recorder.requests()
        #expect(requests.count == 2)
        #expect(requests[0].identifiers.first?.type == .arxiv)
        #expect(requests[1].identifiers.first?.type == .doi)
        #expect(model.items.first?.doi == "10.5555/fallback-doi")
    }

    @Test("import does not leave orphan item when file copy fails")
    func importFailureDoesNotPersistOrphanItem() async throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let missingFile = tempDirectory.appendingPathComponent("missing.pdf")
        let attachmentsDirectory = tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        let attachmentStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)

        let model = makeAppModel(
            providers: [MockDOIMetadataProvider()],
            attachmentStore: attachmentStore
        )
        await model.refreshItems()

        model.importAttachments(urls: [missingFile], mode: .createNewItemPerFile)
        try await waitUntil(timeout: 3.0) { !model.isImportingAttachments }

        #expect(model.items.isEmpty)
        #expect(model.statusMessage == "Import failed")
    }

    @Test("import surfaces new item before slow PDF enrichment completes")
    func importShowsItemBeforeSlowEnrichmentFinishes() async throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let sourceFile = try makeFile(named: "slow.pdf", contents: Data("dummy".utf8), in: tempDirectory)
        let attachmentsDirectory = tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        let attachmentStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)

        let slowExtractor = SlowPDFExtractor(delayNanoseconds: 2_000_000_000)
        let model = makeAppModel(
            providers: [MockDOIMetadataProvider()],
            pdfDOIExtractor: slowExtractor,
            attachmentStore: attachmentStore
        )
        await model.refreshItems()

        model.importAttachments(urls: [sourceFile], mode: .createNewItemPerFile)

        try await waitUntil(timeout: 0.8) { model.items.count == 1 }
        #expect(model.items.first?.title == "slow")

        try await waitUntil(timeout: 4.0) { !model.isImportingAttachments }
    }
}
