@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("AppModel DOI entry")
@MainActor
struct AppModelDOITests {
    @Test("MockDOIProvider returns record for known DOI")
    func mockDOIProviderReturnsRecordForDOI() {
        let provider = MockDOIMetadataProvider()
        let request = MetadataResolutionRequest(
            identifiers: [Identifier(type: .doi, value: "10.1038/nature12373")]
        )
        let records = provider.resolve(request)
        #expect(records.count == 1)
        #expect(records.first?.title == "Nanometre-scale thermometry in a living cell")
    }

    @Test("addByDOI success updates state and status lifecycle")
    func addByDOISuccessUpdatesStateAndStatusLifecycle() async throws {
        let doi = "10.1038/nature12373"
        let provider = StubMetadataProvider(
            records: [
                CanonicalMetadataRecord(
                    title: "A Great Paper",
                    creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
                    publicationYear: 1843,
                    itemType: .article,
                    identifiers: [Identifier(type: .doi, value: doi)],
                    confidence: 0.95,
                    provenance: MetadataProvenance(providerName: "stub-provider")
                )
            ],
            delayNanoseconds: 50_000_000
        )
        let model = makeAppModel(providers: [provider])
        await model.refreshItems()

        model.doiInput = doi
        model.addByDOI()

        #expect(model.isResolvingDOI)
        #expect(model.statusMessage == "Resolving DOI \(doi)...")

        try await waitUntil { !model.isResolvingDOI }

        #expect(model.statusMessage == "Added: A Great Paper")
        #expect(model.doiInput.isEmpty)
        #expect(model.items.count == 1)
        #expect(model.items.first?.doi == doi)
        #expect(model.selectedItemID != nil)
        #expect(model.citation.preview.contains("[apa]"))
    }

    @Test("addByDOI no match sets failure status and stops resolving")
    func addByDOINoMatchSetsFailureStatusAndStopsResolving() async throws {
        let doi = "10.1000/unknown"
        let provider = StubMetadataProvider(records: [], delayNanoseconds: 50_000_000)
        let model = makeAppModel(providers: [provider])
        await model.refreshItems()

        model.doiInput = doi
        model.addByDOI()

        #expect(model.isResolvingDOI)
        #expect(model.statusMessage == "Resolving DOI \(doi)...")

        try await waitUntil { !model.isResolvingDOI }

        #expect(model.statusMessage == "No metadata found for \(doi)")
        #expect(model.items.isEmpty)
        #expect(model.doiInput == doi)
    }

    @Test("addByDOI rejects empty input immediately")
    func addByDOIRejectsEmptyInputImmediately() {
        let model = makeAppModel(providers: [NoopMetadataProvider()])
        model.doiInput = "   "
        model.addByDOI()

        #expect(!model.isResolvingDOI)
        #expect(model.statusMessage == "Enter a DOI first")
    }

    @Test("addByDOI normalizes DOI input and metadata whitespace")
    func addByDOINormalizesDOIInputAndMetadataWhitespace() async throws {
        let provider = StubMetadataProvider(
            records: [
                CanonicalMetadataRecord(
                    title: "  A   Great   Paper  ",
                    creators: [Creator(givenName: "  Ada  ", familyName: "  Lovelace ")],
                    publicationYear: 1843,
                    itemType: .article,
                    identifiers: [Identifier(type: .doi, value: "10.1038/NATURE12373")],
                    confidence: 0.95,
                    provenance: MetadataProvenance(providerName: "stub-provider")
                )
            ],
            delayNanoseconds: 20_000_000
        )
        let model = makeAppModel(providers: [provider])
        await model.refreshItems()

        model.doiInput = "  DOI: 10.1038/NATURE12373  "
        model.addByDOI()
        try await waitUntil { !model.isResolvingDOI }

        #expect(model.items.count == 1)
        #expect(model.items.first?.doi == "10.1038/nature12373")
        #expect(model.items.first?.title == "A Great Paper")
        #expect(model.items.first?.creators.first?.displayName == "Ada Lovelace")
    }
}
