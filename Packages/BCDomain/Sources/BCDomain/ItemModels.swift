import Foundation
import BCCommon

public struct BCItem: Identifiable, Hashable, Codable, Sendable {
	public var id: UUID
	public var title: String
	public var identifiers: [Identifier]
	public var itemType: ItemType
	public var creators: [Creator]
	public var publicationYear: Int?
	public var createdAt: Date
	public var updatedAt: Date

	public init(
		id: UUID = UUID(),
		title: String,
		identifiers: [Identifier] = [],
		itemType: ItemType = .unknown,
		creators: [Creator] = [],
		publicationYear: Int? = nil,
		createdAt: Date = .now,
		updatedAt: Date = .now
	) {
		self.id = id
		self.title = title
		self.identifiers = identifiers
		self.itemType = itemType
		self.creators = creators
		self.publicationYear = publicationYear
		self.createdAt = createdAt
		self.updatedAt = updatedAt
	}

	/// Convenience accessor for the first DOI identifier value.
	public var doi: String? {
		identifiers.first { $0.type == .doi }?.value
	}

	public var displaySubtitle: String {
		let creatorPart = creators.first?.displayName ?? "Unknown author"
		let yearPart = publicationYear.map(String.init) ?? "n.d."
		return "\(creatorPart) · \(yearPart)"
	}
}
