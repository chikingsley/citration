@testable import CitrationCore
import Foundation
import Testing

// MARK: - MetadataProviderTests

@Suite("MetadataProviderRegistry")
struct MetadataProviderTests {
    @Test("noop provider produces no records")
    func noopProviderProducesNoRecords() async {
        let registry = MetadataProviderRegistry(providers: [NoopMetadataProvider()])
        let request = MetadataResolutionRequest(
            identifiers: [Identifier(type: .doi, value: "10.1000/example")]
        )

        let result = await registry.resolveAll(request)
        #expect(result.records.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("deduplicates by identifier keeping highest confidence")
    func registryDeduplicatesByIdentifierKeepingHighestConfidence() async {
        let providerA = MockProvider(
            name: "provider-a",
            records: [
                CanonicalMetadataRecord(
                    title: "Example Paper",
                    identifiers: [Identifier(type: .doi, value: "10.1000/example")],
                    confidence: 0.50,
                    provenance: MetadataProvenance(providerName: "provider-a")
                )
            ]
        )

        let providerB = MockProvider(
            name: "provider-b",
            records: [
                CanonicalMetadataRecord(
                    title: "Example Paper",
                    identifiers: [Identifier(type: .doi, value: "10.1000/example")],
                    confidence: 0.95,
                    provenance: MetadataProvenance(providerName: "provider-b")
                )
            ]
        )

        let registry = MetadataProviderRegistry(providers: [providerA, providerB])
        let request = MetadataResolutionRequest(
            identifiers: [Identifier(type: .doi, value: "10.1000/example")]
        )

        let result = await registry.resolveAll(request)
        #expect(result.records.count == 1)
        #expect(result.records.first?.provenance.providerName == "provider-b")
    }

    @Test("records field conflicts before deduplicating")
    func registryRecordsFieldConflictsBeforeDeduplicating() async {
        let doi = "10.1000/example"
        let providerA = MockProvider(
            name: "provider-a",
            records: [
                CanonicalMetadataRecord(
                    title: "Example Paper",
                    publicationYear: 2023,
                    itemType: .preprint,
                    identifiers: [Identifier(type: .doi, value: doi)],
                    confidence: 0.50,
                    provenance: MetadataProvenance(providerName: "provider-a")
                )
            ]
        )

        let providerB = MockProvider(
            name: "provider-b",
            records: [
                CanonicalMetadataRecord(
                    title: "Example Paper Revised",
                    publicationYear: 2024,
                    itemType: .article,
                    identifiers: [Identifier(type: .doi, value: doi)],
                    confidence: 0.95,
                    provenance: MetadataProvenance(providerName: "provider-b")
                )
            ]
        )

        let registry = MetadataProviderRegistry(providers: [providerA, providerB])
        let result = await registry.resolveAll(
            MetadataResolutionRequest(identifiers: [Identifier(type: .doi, value: doi)])
        )

        #expect(result.records.count == 1)
        #expect(result.bestMatch?.provenance.providerName == "provider-b")
        #expect(Set(result.conflicts.map(\.field)) == [.title, .publicationYear, .itemType])
        #expect(result.conflicts.allSatisfy { $0.preferredProvider == "provider-b" })
        #expect(result.conflicts.allSatisfy { $0.alternateProvider == "provider-a" })
    }

    @Test("collects warning when provider throws")
    func registryCollectsWarningWhenProviderThrows() async {
        let registry = MetadataProviderRegistry(
            providers: [
                ThrowingProvider(name: "failing", errorMessage: "network timeout"),
                NoopMetadataProvider(name: "noop"),
            ]
        )
        let request = MetadataResolutionRequest(
            identifiers: [Identifier(type: .doi, value: "10.1000/example")]
        )

        let result = await registry.resolveAll(request)
        #expect(result.records.isEmpty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].contains("failing"))
        #expect(result.warnings[0].contains("network timeout"))
    }

    @Test("deduplicates by title and year when identifiers missing")
    func registryDeduplicatesByTitleAndYearWhenIdentifiersMissing() async {
        let providerA = MockProvider(
            name: "provider-a",
            records: [
                CanonicalMetadataRecord(
                    title: "  Example Paper  ",
                    publicationYear: 2024,
                    confidence: 0.40,
                    provenance: MetadataProvenance(providerName: "provider-a")
                )
            ]
        )

        let providerB = MockProvider(
            name: "provider-b",
            records: [
                CanonicalMetadataRecord(
                    title: "example paper",
                    publicationYear: 2024,
                    confidence: 0.85,
                    provenance: MetadataProvenance(providerName: "provider-b")
                )
            ]
        )

        let registry = MetadataProviderRegistry(providers: [providerA, providerB])
        let request = MetadataResolutionRequest(
            identifiers: [Identifier(type: .doi, value: "10.1000/example")]
        )

        let result = await registry.resolveAll(request)
        #expect(result.records.count == 1)
        #expect(result.records.first?.provenance.providerName == "provider-b")
    }

    @Test("bestMatch returns record with highest confidence")
    func bestMatchReturnsHighestConfidence() async {
        let provider = MockProvider(
            name: "multi",
            records: [
                CanonicalMetadataRecord(
                    title: "Low",
                    identifiers: [Identifier(type: .doi, value: "10.1000/low")],
                    confidence: 0.30,
                    provenance: MetadataProvenance(providerName: "multi")
                ),
                CanonicalMetadataRecord(
                    title: "High",
                    identifiers: [Identifier(type: .doi, value: "10.1000/high")],
                    confidence: 0.99,
                    provenance: MetadataProvenance(providerName: "multi")
                ),
            ]
        )

        let registry = MetadataProviderRegistry(providers: [provider])
        let request = MetadataResolutionRequest(
            identifiers: [Identifier(type: .doi, value: "10.1000/any")]
        )

        let result = await registry.resolveAll(request)
        #expect(result.bestMatch?.title == "High")
    }
}

// MARK: - MockProvider

private struct MockProvider: MetadataProvider {
    let name: String
    let records: [CanonicalMetadataRecord]

    func resolve(_ request: MetadataResolutionRequest) -> [CanonicalMetadataRecord] {
        _ = request
        return records
    }
}

// MARK: - ThrowingProvider

private struct ThrowingProvider: MetadataProvider {
    let name: String
    let errorMessage: String

    func resolve(_ request: MetadataResolutionRequest) throws -> [CanonicalMetadataRecord] {
        _ = request
        throw MetadataProviderError.providerFailure(provider: name, details: errorMessage)
    }
}
