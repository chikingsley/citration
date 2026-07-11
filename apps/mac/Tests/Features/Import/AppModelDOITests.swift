@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("AppModel DOI entry")
@MainActor
struct AppModelDOITests {
    @Test("DOI identifier entry updates state and status lifecycle")
    func doiEntryUpdatesStateAndStatusLifecycle() async throws {
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
        let model = makeAppModel(
            providers: [provider],
            citationFormatter: CSLCitationFormatter()
        )
        await model.refreshItems()

        model.importer.identifierKind = .doi
        model.importer.identifierInput = doi
        model.importer.addByIdentifier()

        #expect(model.importer.isResolvingIdentifier)
        #expect(model.statusMessage == "Resolving DOI \(doi)...")

        try await waitUntil { !model.importer.isResolvingIdentifier }

        #expect(model.statusMessage == "Added: A Great Paper")
        #expect(model.importer.identifierInput.isEmpty)
        #expect(model.items.count == 1)
        #expect(model.items.first?.doi == doi)
        #expect(model.selectedItemID != nil)
        try await waitUntil(timeout: 5) {
            model.citation.preview.contains("A Great Paper")
        }
        #expect(model.citation.preview.contains("Lovelace"))
        #expect(model.citation.preview.contains("1843"))
        #expect(model.citation.preview.contains("A Great Paper"))
    }

    @Test("DOI identifier with no match sets failure status and stops resolving")
    func doiWithNoMatchSetsFailureStatusAndStopsResolving() async throws {
        let doi = "10.1000/unknown"
        let provider = StubMetadataProvider(records: [], delayNanoseconds: 50_000_000)
        let model = makeAppModel(providers: [provider])
        await model.refreshItems()

        model.importer.identifierKind = .doi
        model.importer.identifierInput = doi
        model.importer.addByIdentifier()

        #expect(model.importer.isResolvingIdentifier)
        #expect(model.statusMessage == "Resolving DOI \(doi)...")

        try await waitUntil { !model.importer.isResolvingIdentifier }

        #expect(model.statusMessage == "No metadata found for DOI \(doi)")
        #expect(model.items.isEmpty)
        #expect(model.importer.identifierInput == doi)
    }

    @Test("DOI identifier rejects empty input immediately")
    func doiRejectsEmptyInputImmediately() {
        let model = makeAppModel(providers: [])
        model.importer.identifierKind = .doi
        model.importer.identifierInput = "   "
        model.importer.addByIdentifier()

        #expect(!model.importer.isResolvingIdentifier)
        #expect(model.statusMessage == "Enter DOI first")
    }

    @Test("DOI identifier normalizes input and metadata whitespace")
    func doiNormalizesInputAndMetadataWhitespace() async throws {
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

        model.importer.identifierKind = .doi
        model.importer.identifierInput = "  DOI: 10.1038/NATURE12373  "
        model.importer.addByIdentifier()
        try await waitUntil { !model.importer.isResolvingIdentifier }

        #expect(model.items.count == 1)
        #expect(model.items.first?.doi == "10.1038/nature12373")
        #expect(model.items.first?.title == "A Great Paper")
        #expect(model.items.first?.creators.first?.displayName == "Ada Lovelace")
    }

    @Test("ISBN and arXiv inputs use their production normalizers")
    func additionalIdentifierNormalizers() async throws {
        let model = makeAppModel(providers: [])

        model.importer.identifierKind = .isbn
        model.importer.identifierInput = "978-0-306-40615-7"
        model.importer.addByIdentifier()
        #expect(model.statusMessage == "Resolving ISBN 9780306406157...")
        try await waitUntil { !model.importer.isResolvingIdentifier }

        model.importer.identifierKind = .arxiv
        model.importer.identifierInput = "arXiv:2401.01234v2"
        model.importer.addByIdentifier()
        #expect(model.statusMessage == "Resolving arXiv 2401.01234...")
        try await waitUntil { !model.importer.isResolvingIdentifier }
    }
}
