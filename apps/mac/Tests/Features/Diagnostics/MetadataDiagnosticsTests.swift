@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - MetadataDiagnosticsTests

@Suite("Metadata diagnostics")
@MainActor
struct MetadataDiagnosticsTests {
    @Test("addByDOI preserves metadata conflict diagnostics")
    func addByDOIPreservesMetadataConflictDiagnostics() async throws {
        let doi = "10.1000/disagree"
        let provider = ConflictingMetadataProvider(doi: doi)
        let model = makeAppModel(providers: [provider])
        await model.refreshItems()

        model.importer.identifierKind = .doi
        model.importer.identifierInput = doi
        model.importer.addByIdentifier()
        try await waitUntil { !model.importer.isResolvingIdentifier }

        #expect(model.statusMessage == "Added: Published Title · check metadata")
        #expect(model.items.first?.title == "Published Title")
        #expect(Set(model.importer.metadataConflicts.map(\.field)) == [.title, .publicationYear, .itemType])
        #expect(model.importer.metadataWarnings.isEmpty)
    }
}

// MARK: - ConflictingMetadataProvider

private struct ConflictingMetadataProvider: MetadataProvider {
    let name = "conflicting-metadata"
    let doi: String

    func resolve(_ request: MetadataResolutionRequest) -> [CanonicalMetadataRecord] {
        _ = request
        return [
            CanonicalMetadataRecord(
                title: "Draft Title",
                publicationYear: 2023,
                itemType: .preprint,
                identifiers: [Identifier(type: .doi, value: doi)],
                confidence: 0.60,
                provenance: MetadataProvenance(providerName: "OpenAlex")
            ),
            CanonicalMetadataRecord(
                title: "Published Title",
                publicationYear: 2024,
                itemType: .article,
                identifiers: [Identifier(type: .doi, value: doi)],
                confidence: 0.95,
                provenance: MetadataProvenance(providerName: "Crossref")
            ),
        ]
    }
}
