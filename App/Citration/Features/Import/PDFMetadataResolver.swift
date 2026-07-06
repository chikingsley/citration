import CitrationCore
import Foundation

/// Runs the identifier-then-title resolution chain for PDF-derived
/// metadata candidates, reporting every resolution result so the
/// caller can surface diagnostics.
@MainActor
struct PDFMetadataResolver {
    let registry: MetadataProviderRegistry
    let onResult: (MetadataResolutionResult) -> Void

    func resolve(
        candidates: PDFMetadataCandidates,
        fallbackTitleQuery: String?
    ) async -> CanonicalMetadataRecord? {
        for type in [IdentifierType.arxiv, .doi, .isbn] {
            if let record = await resolveMetadata(candidates: candidates, type: type) {
                return record
            }
        }

        let queries = MetadataMerging.titleQueries(from: candidates, fallbackTitleQuery: fallbackTitleQuery)
        return await resolveMetadata(titleQueries: queries)
    }

    func resolveMetadata(
        candidates: PDFMetadataCandidates,
        type: IdentifierType
    ) async -> CanonicalMetadataRecord? {
        let identifiers = candidates.identifiers.filter { $0.type == type }
        for identifier in identifiers {
            if let record = await resolveMetadata(identifiers: [identifier], freeTextQuery: nil) {
                return record
            }
        }
        return nil
    }

    func resolveMetadata(titleQueries: [String]) async -> CanonicalMetadataRecord? {
        for title in titleQueries {
            if let record = await resolveMetadata(identifiers: [], freeTextQuery: title) {
                return record
            }
        }
        return nil
    }

    func resolveMetadata(
        identifiers: [Identifier],
        freeTextQuery: String?
    ) async -> CanonicalMetadataRecord? {
        let request = MetadataResolutionRequest(
            identifiers: identifiers,
            freeTextQuery: freeTextQuery
        )
        let result = await registry.resolveAll(request)
        onResult(result)
        return result.bestMatch
    }
}
