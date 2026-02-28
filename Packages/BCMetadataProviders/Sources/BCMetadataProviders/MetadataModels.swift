import Foundation
import BCCommon

public struct MetadataProvenance: Hashable, Codable, Sendable {
	public var providerName: String
	public var sourceRecordID: String?
	public var fieldSources: [String: String]

	public init(providerName: String, sourceRecordID: String? = nil, fieldSources: [String: String] = [:]) {
		self.providerName = providerName
		self.sourceRecordID = sourceRecordID
		self.fieldSources = fieldSources
	}
}

public struct CanonicalMetadataRecord: Identifiable, Hashable, Codable, Sendable {
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
}

public struct MetadataResolutionRequest: Hashable, Sendable {
	public var identifiers: [Identifier]
	public var freeTextQuery: String?

	public init(identifiers: [Identifier], freeTextQuery: String? = nil) {
		self.identifiers = identifiers
		self.freeTextQuery = freeTextQuery
	}
}

public struct MetadataResolutionResult: Sendable {
	public var records: [CanonicalMetadataRecord]
	public var warnings: [String]

	public init(records: [CanonicalMetadataRecord], warnings: [String] = []) {
		self.records = records
		self.warnings = warnings
	}

	public var bestMatch: CanonicalMetadataRecord? {
		records.max { $0.confidence < $1.confidence }
	}
}
