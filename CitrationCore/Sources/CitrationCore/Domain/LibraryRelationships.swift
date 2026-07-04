import Foundation

public enum LibraryRelationshipKind: String, Codable, CaseIterable, Sendable {
    case cites
    case citedBy
    case series
    case sameCreator
    case sameInstitution
    case sameTopic
    case supplement
    case userLinked

    public var displayLabel: String {
        switch self {
        case .cites:
            return "Cites"
        case .citedBy:
            return "Cited by"
        case .series:
            return "Series"
        case .sameCreator:
            return "Same author"
        case .sameInstitution:
            return "Same institution"
        case .sameTopic:
            return "Same topic"
        case .supplement:
            return "Supplement"
        case .userLinked:
            return "Linked"
        }
    }
}

public struct LibraryRelationship: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sourceItemID: UUID
    public var targetItemID: UUID
    public var kind: LibraryRelationshipKind
    public var confidence: Double
    public var note: String?

    public init(
        id: UUID = UUID(),
        sourceItemID: UUID,
        targetItemID: UUID,
        kind: LibraryRelationshipKind,
        confidence: Double,
        note: String? = nil
    ) {
        self.id = id
        self.sourceItemID = sourceItemID
        self.targetItemID = targetItemID
        self.kind = kind
        self.confidence = min(max(confidence, 0), 1)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = trimmedNote?.isEmpty == false ? trimmedNote : nil
    }
}

public enum RecommendationReason: Hashable, Codable, Sendable {
    case sharedCreator(String)
    case sharedIdentifier(IdentifierType)
    case samePublicationYear(Int)
    case openAlexRelatedWork(String)
    case userLinked(LibraryRelationshipKind)

    public var displayLabel: String {
        switch self {
        case .sharedCreator(let name):
            return "Shared author: \(name)"
        case .sharedIdentifier(let type):
            return "Shared \(type.rawValue.uppercased())"
        case .samePublicationYear(let year):
            return "Same year: \(year)"
        case .openAlexRelatedWork(let workID):
            return "OpenAlex related work: \(workID)"
        case .userLinked(let kind):
            return "Linked: \(kind.displayLabel)"
        }
    }
}

public struct LibraryRecommendation: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sourceItemID: UUID
    public var candidateItemID: UUID
    public var score: Double
    public var reasons: [RecommendationReason]

    public init(
        id: UUID = UUID(),
        sourceItemID: UUID,
        candidateItemID: UUID,
        score: Double,
        reasons: [RecommendationReason]
    ) {
        self.id = id
        self.sourceItemID = sourceItemID
        self.candidateItemID = candidateItemID
        self.score = min(max(score, 0), 1)
        self.reasons = reasons
    }
}

public struct LibraryInsightEngine: Sendable {
    public init() {}

    public func recommendations(
        for item: BCItem,
        in candidates: [BCItem],
        relationships: [LibraryRelationship] = [],
        limit: Int = 5
    ) -> [LibraryRecommendation] {
        let candidateItems = candidates.filter { $0.id != item.id }
        let inferred = candidateItems.compactMap { candidate in
            recommendation(source: item, candidate: candidate)
        }

        let linked = linkedRecommendations(
            for: item,
            candidates: candidateItems,
            relationships: relationships
        )

        return mergedRecommendations(inferred + linked)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.candidateItemID.uuidString < rhs.candidateItemID.uuidString
                }
                return lhs.score > rhs.score
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private func linkedRecommendations(
        for item: BCItem,
        candidates: [BCItem],
        relationships: [LibraryRelationship]
    ) -> [LibraryRecommendation] {
        let candidateIDs = Set(candidates.map(\.id))

        return relationships.compactMap { relationship in
            let candidateID: UUID?
            if relationship.sourceItemID == item.id {
                candidateID = relationship.targetItemID
            } else if relationship.targetItemID == item.id {
                candidateID = relationship.sourceItemID
            } else {
                candidateID = nil
            }

            guard let candidateID,
                  candidateIDs.contains(candidateID) else {
                return nil
            }

            return LibraryRecommendation(
                sourceItemID: item.id,
                candidateItemID: candidateID,
                score: max(relationship.confidence, 0.95),
                reasons: [.userLinked(relationship.kind)]
            )
        }
    }

    private func mergedRecommendations(_ recommendations: [LibraryRecommendation]) -> [LibraryRecommendation] {
        var merged = [UUID: LibraryRecommendation]()

        for recommendation in recommendations {
            guard var existing = merged[recommendation.candidateItemID] else {
                merged[recommendation.candidateItemID] = recommendation
                continue
            }

            existing.score = min(max(existing.score, recommendation.score), 1)
            existing.reasons = existing.reasons.mergingUnique(recommendation.reasons)
            merged[recommendation.candidateItemID] = existing
        }

        return Array(merged.values)
    }

    private func recommendation(source: BCItem, candidate: BCItem) -> LibraryRecommendation? {
        var reasons = [RecommendationReason]()
        var score = 0.0

        let sharedCreators = source.normalizedCreatorNames.intersection(candidate.normalizedCreatorNames)
        if let creator = sharedCreators.min() {
            reasons.append(.sharedCreator(creator))
            score += 0.60
        }

        if let sharedIdentifier = sharedIdentifierType(source: source, candidate: candidate) {
            reasons.append(.sharedIdentifier(sharedIdentifier))
            score += 0.80
        }

        if let year = source.publicationYear,
           candidate.publicationYear == year {
            reasons.append(.samePublicationYear(year))
            score += 0.10
        }

        guard !reasons.isEmpty else {
            return nil
        }

        return LibraryRecommendation(
            sourceItemID: source.id,
            candidateItemID: candidate.id,
            score: score,
            reasons: reasons
        )
    }

    private func sharedIdentifierType(source: BCItem, candidate: BCItem) -> IdentifierType? {
        let sourceIdentifiers = Set(source.identifiers)
        return candidate.identifiers.first { sourceIdentifiers.contains($0) }?.type
    }
}

private extension Array where Element: Hashable {
    func mergingUnique(_ values: [Element]) -> [Element] {
        var seen = Set(self)
        var result = self
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

private extension BCItem {
    var normalizedCreatorNames: Set<String> {
        Set(creators.map(\.displayName).map(Self.normalizeRecommendationToken).filter { !$0.isEmpty })
    }

    static func normalizeRecommendationToken(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
