import Foundation

public struct BCItem: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        title: String,
        identifiers: [Identifier] = [],
        itemType: ItemType = .unknown,
        creators: [Creator] = [],
        publicationYear: Int? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.identifiers = identifiers
        self.itemType = itemType
        self.creators = creators
        self.publicationYear = publicationYear
        self.tags = Self.normalizedTags(tags)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        identifiers = try container.decode([Identifier].self, forKey: .identifiers)
        itemType = try container.decode(ItemType.self, forKey: .itemType)
        creators = try container.decode([Creator].self, forKey: .creators)
        publicationYear = try container.decodeIfPresent(Int.self, forKey: .publicationYear)
        tags = try Self.normalizedTags(container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    // MARK: Public

    public var id: UUID
    public var title: String
    public var identifiers: [Identifier]
    public var itemType: ItemType
    public var creators: [Creator]
    public var publicationYear: Int?
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    /// Convenience accessor for the first DOI identifier value.
    public var doi: String? {
        identifiers.first { $0.type == .doi }?.value
    }

    public var displaySubtitle: String {
        let creatorPart = creators.first?.displayName ?? "Unknown author"
        let yearPart = publicationYear.map(String.init) ?? "n.d."
        return "\(creatorPart) · \(yearPart)"
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result = [String]()

        for tag in tags {
            let collapsed = tag
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !collapsed.isEmpty else {
                continue
            }

            if seen.insert(collapsed.lowercased()).inserted {
                result.append(collapsed)
            }
        }

        return result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(identifiers, forKey: .identifiers)
        try container.encode(itemType, forKey: .itemType)
        try container.encode(creators, forKey: .creators)
        try container.encodeIfPresent(publicationYear, forKey: .publicationYear)
        try container.encode(tags, forKey: .tags)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case identifiers
        case itemType
        case creators
        case publicationYear
        case tags
        case createdAt
        case updatedAt
    }
}
