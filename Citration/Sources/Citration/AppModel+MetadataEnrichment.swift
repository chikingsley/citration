import Foundation
import CitrationCore

extension AppModel {
    func addByDOI() {
        guard let doi = normalizedDOIInput() else {
            return
        }

        clearMetadataDiagnostics()
        isResolvingDOI = true
        statusMessage = "Resolving DOI \(doi)..."

        Task {
            let request = MetadataResolutionRequest(
                identifiers: [Identifier(type: .doi, value: doi)]
            )
            let result = await metadataRegistry.resolveAll(request)
            recordMetadataDiagnostics(result)

            guard let best = result.bestMatch else {
                isResolvingDOI = false
                statusMessage = "No metadata found for \(doi)"
                return
            }

            let fallbackItem = BCItem(title: "Untitled Item")
            let item = BCItem(
                title: normalizedTitle(best.title) ?? "Untitled Item",
                identifiers: mergeIdentifiers(
                    best.identifiers + [Identifier(type: .doi, value: doi)],
                    into: fallbackItem
                ).identifiers,
                itemType: best.itemType,
                creators: normalizedCreators(best.creators),
                publicationYear: best.publicationYear
            )

            await store.upsert(item)
            selectedItemID = item.id
            await refreshItems()
            doiInput = ""
            isResolvingDOI = false
            statusMessage = "Added: \(item.title)"
            appendMetadataDiagnosticsStatus()
        }
    }

    func inferredTitle(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let replaced = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .bcCollapsedWhitespace()
        return replaced.isEmpty ? "Untitled Item" : replaced
    }

    func enrichImportedAttachment(
        item: BCItem,
        attachment: LocalAttachment
    ) async -> AttachmentEnrichment {
        guard shouldAttemptDOIExtraction(for: attachment), item.doi == nil else {
            return AttachmentEnrichment(item: item, detectedDOI: nil)
        }

        let candidates = await pdfDOIExtractor.extractCandidates(from: attachment.localURL)
        let fallbackTitleQuery = metadataFallbackTitle(for: item, attachment: attachment)

        if let best = await resolveMetadataForPDFCandidates(candidates, fallbackTitleQuery: fallbackTitleQuery) {
            let enriched = mergeMetadata(best, into: item, fallbackDOI: candidates.detectedDOI)
            await store.upsert(enriched)
            return AttachmentEnrichment(item: enriched, detectedDOI: candidates.detectedDOI)
        }

        guard !candidates.isEmpty else {
            return AttachmentEnrichment(item: item, detectedDOI: nil)
        }

        let withDetectedIdentifiers = mergeIdentifiers(candidates.identifiers, into: item)
        await store.upsert(withDetectedIdentifiers)
        return AttachmentEnrichment(item: withDetectedIdentifiers, detectedDOI: candidates.detectedDOI)
    }

    func shouldAttemptDOIExtraction(for attachment: LocalAttachment) -> Bool {
        attachment.documentFormat == .pdf
    }

    func clearMetadataDiagnostics() {
        metadataWarnings = []
        metadataConflicts = []
    }

    func recordMetadataDiagnostics(_ result: MetadataResolutionResult) {
        metadataWarnings = result.warnings
        metadataConflicts = result.conflicts
    }

    func appendMetadataDiagnosticsStatus() {
        guard !metadataConflicts.isEmpty else {
            return
        }

        statusMessage += " · check metadata"
    }
}

private extension AppModel {
    func normalizedDOIInput() -> String? {
        guard let trimmed = doiInput.bcTrimmedNonEmpty else {
            statusMessage = "Enter a DOI first"
            return nil
        }
        guard let doi = DOIParsing.normalizeCandidate(trimmed) else {
            statusMessage = "Enter a valid DOI"
            return nil
        }
        return doi
    }

    func resolveMetadataForPDFCandidates(
        _ candidates: PDFMetadataCandidates,
        fallbackTitleQuery: String?
    ) async -> CanonicalMetadataRecord? {
        for type in [IdentifierType.arxiv, .doi, .isbn] {
            if let record = await resolveMetadata(candidates: candidates, type: type) {
                return record
            }
        }

        let queries = titleQueries(from: candidates, fallbackTitleQuery: fallbackTitleQuery)
        return await resolveMetadata(titleQueries: queries)
    }

    func resolveMetadata(candidates: PDFMetadataCandidates, type: IdentifierType) async -> CanonicalMetadataRecord? {
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

    func titleQueries(from candidates: PDFMetadataCandidates, fallbackTitleQuery: String?) -> [String] {
        var titleQueries = candidates.titleHints
        if let fallbackTitleQuery {
            let hasExistingQuery = titleQueries.contains {
                $0.caseInsensitiveCompare(fallbackTitleQuery) == .orderedSame
            }
            if !hasExistingQuery {
                titleQueries.append(fallbackTitleQuery)
            }
        }
        return titleQueries
    }

    func metadataFallbackTitle(for item: BCItem, attachment: LocalAttachment) -> String? {
        if let title = normalizedTitle(item.title), title != "Untitled Item" {
            return title
        }

        let attachmentTitle = inferredTitle(from: attachment.localURL)
        guard attachmentTitle != "Untitled Item" else {
            return nil
        }
        return normalizedTitle(attachmentTitle)
    }

    func resolveMetadata(
        identifiers: [Identifier],
        freeTextQuery: String?
    ) async -> CanonicalMetadataRecord? {
        let request = MetadataResolutionRequest(
            identifiers: identifiers,
            freeTextQuery: freeTextQuery
        )
        let result = await metadataRegistry.resolveAll(request)
        recordMetadataDiagnostics(result)
        return result.bestMatch
    }

    func mergeMetadata(
        _ record: CanonicalMetadataRecord,
        into item: BCItem,
        fallbackDOI: String?
    ) -> BCItem {
        let fallbackIdentifiers = fallbackDOI.map {
            [Identifier(type: .doi, value: $0)]
        } ?? []

        let mergedIdentifiers = mergeIdentifiers(record.identifiers + fallbackIdentifiers, into: item).identifiers
        let recordCreators = normalizedCreators(record.creators)
        let itemCreators = normalizedCreators(item.creators)

        return BCItem(
            id: item.id,
            title: normalizedTitle(record.title) ?? normalizedTitle(item.title) ?? "Untitled Item",
            identifiers: mergedIdentifiers,
            itemType: record.itemType == .unknown ? item.itemType : record.itemType,
            creators: recordCreators.isEmpty ? itemCreators : recordCreators,
            publicationYear: record.publicationYear ?? item.publicationYear,
            tags: item.tags,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }

    func mergeIdentifiers(_ incoming: [Identifier], into item: BCItem) -> BCItem {
        var merged = item.identifiers
        var seen = Set<String>(merged.map(identifierDedupeKey(for:)))

        for identifier in incoming {
            guard let normalized = normalizedIdentifier(identifier) else {
                continue
            }

            let key = identifierDedupeKey(for: normalized)
            if seen.insert(key).inserted {
                merged.append(normalized)
            }
        }

        return BCItem(
            id: item.id,
            title: item.title,
            identifiers: merged,
            itemType: item.itemType,
            creators: item.creators,
            publicationYear: item.publicationYear,
            tags: item.tags,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }

    func normalizedIdentifier(_ identifier: Identifier) -> Identifier? {
        var normalized = identifier
        if normalized.type == .doi {
            guard let normalizedDOI = DOIParsing.normalizeCandidate(normalized.value) else {
                return nil
            }
            normalized.value = normalizedDOI
        }

        normalized.value = normalized.value.bcCollapsedWhitespace()
        return normalized.value.isEmpty ? nil : normalized
    }

    func normalizedTitle(_ raw: String) -> String? {
        raw.bcTrimmedNonEmpty
    }

    func normalizedCreators(_ creators: [Creator]) -> [Creator] {
        creators.compactMap { creator in
            let literal = creator.literalName?.bcTrimmedNonEmpty
            let given = creator.givenName?.bcTrimmedNonEmpty
            let family = creator.familyName?.bcTrimmedNonEmpty

            if literal == nil, given == nil, family == nil {
                return nil
            }

            return Creator(
                id: creator.id,
                givenName: given,
                familyName: family,
                literalName: literal
            )
        }
    }

    func identifierDedupeKey(for identifier: Identifier) -> String {
        if identifier.type == .doi, let normalizedDOI = DOIParsing.normalizeCandidate(identifier.value) {
            return "\(identifier.type.rawValue):\(normalizedDOI.lowercased())"
        }
        return "\(identifier.type.rawValue):\(identifier.value.lowercased())"
    }
}

struct AttachmentEnrichment {
    var item: BCItem
    var detectedDOI: String?
}
