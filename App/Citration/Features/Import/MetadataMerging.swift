import CitrationCore
import Foundation

/// Pure helpers for merging resolved metadata records into library items.
enum MetadataMerging {
    static func titleQueries(from candidates: PDFMetadataCandidates, fallbackTitleQuery: String?) -> [String] {
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

    static func metadataFallbackTitle(for item: BCItem, attachment: LocalAttachment) -> String? {
        if let title = normalizedTitle(item.title), title != "Untitled Item" {
            return title
        }

        let attachmentTitle = inferredTitle(from: attachment.localURL)
        guard attachmentTitle != "Untitled Item" else {
            return nil
        }
        return normalizedTitle(attachmentTitle)
    }

    static func mergeMetadata(
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

    static func mergeIdentifiers(_ incoming: [Identifier], into item: BCItem) -> BCItem {
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

    static func normalizedIdentifier(_ identifier: Identifier) -> Identifier? {
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

    static func normalizedTitle(_ raw: String) -> String? {
        raw.bcTrimmedNonEmpty
    }

    static func normalizedCreators(_ creators: [Creator]) -> [Creator] {
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

    static func identifierDedupeKey(for identifier: Identifier) -> String {
        if identifier.type == .doi, let normalizedDOI = DOIParsing.normalizeCandidate(identifier.value) {
            return "\(identifier.type.rawValue):\(normalizedDOI.lowercased())"
        }
        return "\(identifier.type.rawValue):\(identifier.value.lowercased())"
    }

    static func inferredTitle(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let replaced = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .bcCollapsedWhitespace()
        return replaced.isEmpty ? "Untitled Item" : replaced
    }
}
