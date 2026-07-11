import Foundation

// MARK: - ZoteroItemTypeDefinition

public struct ZoteroItemTypeDefinition: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(itemType: String, localized: String) {
        self.itemType = itemType
        self.localized = localized
    }

    // MARK: Public

    public let itemType: String
    public let localized: String
}

// MARK: - ZoteroItemFieldDefinition

public struct ZoteroItemFieldDefinition: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(field: String, localized: String) {
        self.field = field
        self.localized = localized
    }

    // MARK: Public

    public let field: String
    public let localized: String
}

// MARK: - ZoteroCreatorTypeDefinition

public struct ZoteroCreatorTypeDefinition: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(creatorType: String, localized: String, primary: Bool? = nil) {
        self.creatorType = creatorType
        self.localized = localized
        self.primary = primary
    }

    // MARK: Public

    public let creatorType: String
    public let localized: String
    public let primary: Bool?
}

// MARK: - ZoteroItemEditingSchema

public struct ZoteroItemEditingSchema: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        itemType: ZoteroItemTypeDefinition,
        fields: [ZoteroItemFieldDefinition],
        creatorTypes: [ZoteroCreatorTypeDefinition]
    ) {
        self.itemType = itemType
        self.fields = fields
        self.creatorTypes = creatorTypes
    }

    // MARK: Public

    public let itemType: ZoteroItemTypeDefinition
    public let fields: [ZoteroItemFieldDefinition]
    public let creatorTypes: [ZoteroCreatorTypeDefinition]

    public var primaryCreatorType: String? {
        creatorTypes.first(where: { $0.primary == true })?.creatorType ?? creatorTypes.first?.creatorType
    }
}
