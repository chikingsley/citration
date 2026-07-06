import Foundation

// MARK: - MetadataProvenance

public struct MetadataProvenance: Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(providerName: String, sourceRecordID: String? = nil, fieldSources: [String: String] = [:]) {
        self.providerName = providerName
        self.sourceRecordID = sourceRecordID
        self.fieldSources = fieldSources
    }

    // MARK: Public

    public var providerName: String
    public var sourceRecordID: String?
    public var fieldSources: [String: String]
}

// MARK: - CanonicalMetadataRecord

public struct CanonicalMetadataRecord: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        title: String,
        creators: [Creator] = [],
        publicationYear: Int? = nil,
        itemType: ItemType = .unknown,
        identifiers: [Identifier] = [],
        abstract: String? = nil,
        sourceURL: URL? = nil,
        confidence: Double,
        provenance: MetadataProvenance,
        rawPayload: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.creators = creators
        self.publicationYear = publicationYear
        self.itemType = itemType
        self.identifiers = identifiers
        self.abstract = abstract
        self.sourceURL = sourceURL
        self.confidence = confidence
        self.provenance = provenance
        self.rawPayload = rawPayload
    }

    // MARK: Public

    public var id: UUID
    public var title: String
    public var creators: [Creator]
    public var publicationYear: Int?
    public var itemType: ItemType
    public var identifiers: [Identifier]
    public var abstract: String?
    public var sourceURL: URL?
    public var confidence: Double
    public var provenance: MetadataProvenance
    public var rawPayload: Data?
}

// MARK: - MetadataConflictField

public enum MetadataConflictField: String, Hashable, Codable, Sendable {
    case title
    case publicationYear
    case itemType
}

// MARK: - MetadataResolutionConflict

public struct MetadataResolutionConflict: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(
        field: MetadataConflictField,
        preferredValue: String,
        alternateValue: String,
        preferredProvider: String,
        alternateProvider: String
    ) {
        self.field = field
        self.preferredValue = preferredValue
        self.alternateValue = alternateValue
        self.preferredProvider = preferredProvider
        self.alternateProvider = alternateProvider
    }

    // MARK: Public

    public var field: MetadataConflictField
    public var preferredValue: String
    public var alternateValue: String
    public var preferredProvider: String
    public var alternateProvider: String

    public var id: String {
        [
            field.rawValue,
            preferredProvider,
            alternateProvider,
            preferredValue,
            alternateValue,
        ].joined(separator: "|")
    }
}

// MARK: - MetadataResolutionRequest

public struct MetadataResolutionRequest: Hashable, Sendable {
    // MARK: Lifecycle

    public init(identifiers: [Identifier], freeTextQuery: String? = nil) {
        self.identifiers = identifiers
        self.freeTextQuery = freeTextQuery
    }

    // MARK: Public

    public var identifiers: [Identifier]
    public var freeTextQuery: String?
}

// MARK: - MetadataResolutionResult

public struct MetadataResolutionResult: Sendable {
    // MARK: Lifecycle

    public init(
        records: [CanonicalMetadataRecord],
        warnings: [String] = [],
        conflicts: [MetadataResolutionConflict] = []
    ) {
        self.records = records
        self.warnings = warnings
        self.conflicts = conflicts
    }

    // MARK: Public

    public var records: [CanonicalMetadataRecord]
    public var warnings: [String]
    public var conflicts: [MetadataResolutionConflict]

    public var bestMatch: CanonicalMetadataRecord? {
        records.max { $0.confidence < $1.confidence }
    }
}
