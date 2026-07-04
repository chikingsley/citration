import Foundation

public enum DocumentFormat: String, Codable, CaseIterable, Sendable {
    case pdf
    case epub
    case html
    case plainText
    case image
    case audio
    case unknown

    public static func infer(fileName: String, contentType: String? = nil) -> DocumentFormat {
        let normalizedContentType = contentType?.lowercased()
        switch normalizedContentType {
        case "application/pdf":
            return .pdf
        case "application/epub+zip", "application/x-ibooks+zip":
            return .epub
        case "text/html", "application/xhtml+xml":
            return .html
        case "text/plain":
            return .plainText
        case let type? where type.hasPrefix("image/"):
            return .image
        case let type? where type.hasPrefix("audio/"):
            return .audio
        default:
            break
        }

        switch fileName.split(separator: ".").last?.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "html", "htm", "xhtml":
            return .html
        case "txt", "md", "markdown":
            return .plainText
        case "png", "jpg", "jpeg", "gif", "heic", "tiff":
            return .image
        case "mp3", "m4a", "aac", "wav", "aiff":
            return .audio
        default:
            return .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .pdf:
            return "PDF"
        case .epub:
            return "EPUB"
        case .html:
            return "HTML"
        case .plainText:
            return "Text"
        case .image:
            return "Image"
        case .audio:
            return "Audio"
        case .unknown:
            return "File"
        }
    }

    public var readerCapabilities: Set<ReaderCapability> {
        switch self {
        case .pdf:
            return [.pageNavigation, .textSelection, .annotations, .tableOfContents]
        case .epub:
            return [.reflowableText, .textSelection, .annotations, .tableOfContents]
        case .html, .plainText:
            return [.reflowableText, .textSelection, .annotations]
        case .audio:
            return [.timeNavigation]
        case .image, .unknown:
            return []
        }
    }

    public var isReadableDocument: Bool {
        !readerCapabilities.isEmpty
    }
}

public enum ReaderCapability: String, Codable, CaseIterable, Sendable {
    case pageNavigation
    case timeNavigation
    case reflowableText
    case textSelection
    case annotations
    case tableOfContents
}

public enum ReaderLocation: Hashable, Codable, Sendable {
    case page(Int)
    case epubCFI(String)
    case textOffset(Int)
    case time(seconds: Double)

    public var displayLabel: String {
        switch self {
        case .page(let page):
            return "Page \(page)"
        case .epubCFI:
            return "EPUB location"
        case .textOffset(let offset):
            return "Text offset \(offset)"
        case .time(let seconds):
            let minutes = Int(seconds) / 60
            let remainder = Int(seconds) % 60
            return "\(minutes):\(String(format: "%02d", remainder))"
        }
    }
}

public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case highlight
    case note
    case underline
}

public enum AnnotationColor: String, Codable, CaseIterable, Sendable {
    case yellow
    case green
    case blue
    case pink
    case purple
}

public struct LibraryAnnotation: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var itemID: UUID
    public var attachmentKey: String
    public var kind: AnnotationKind
    public var location: ReaderLocation?
    public var selectedText: String?
    public var note: String
    public var color: AnnotationColor
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        attachmentKey: String,
        kind: AnnotationKind = .note,
        location: ReaderLocation? = nil,
        selectedText: String? = nil,
        note: String,
        color: AnnotationColor = .yellow,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.itemID = itemID
        self.attachmentKey = attachmentKey
        self.kind = kind
        self.location = location
        self.selectedText = selectedText
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        note.isEmpty && (selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

public struct ReaderProgress: Hashable, Codable, Sendable {
    public var attachmentID: UUID
    public var location: ReaderLocation
    public var fractionComplete: Double?
    public var updatedAt: Date

    public init(
        attachmentID: UUID,
        location: ReaderLocation,
        fractionComplete: Double? = nil,
        updatedAt: Date = .now
    ) {
        self.attachmentID = attachmentID
        self.location = location
        self.fractionComplete = fractionComplete.map { min(max($0, 0), 1) }
        self.updatedAt = updatedAt
    }
}

public enum LibraryRelationshipKind: String, Codable, CaseIterable, Sendable {
    case cites
    case citedBy
    case series
    case sameCreator
    case sameInstitution
    case sameTopic
    case supplement
    case userLinked
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
        self.note = note
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
            return "Linked: \(kind.rawValue)"
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
        limit: Int = 5
    ) -> [LibraryRecommendation] {
        candidates
            .filter { $0.id != item.id }
            .compactMap { candidate in
                recommendation(source: item, candidate: candidate)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.candidateItemID.uuidString < rhs.candidateItemID.uuidString
                }
                return lhs.score > rhs.score
            }
            .prefix(max(0, limit))
            .map { $0 }
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
