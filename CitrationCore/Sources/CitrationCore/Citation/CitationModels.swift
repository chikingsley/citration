import Foundation

public enum CitationOutputFormat: String, Codable, CaseIterable, Sendable {
    case plainText
    case markdown
    case html
}

public struct CitationStyle: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var locale: String

    public init(id: String, title: String, locale: String = "en-US") {
        self.id = id
        self.title = title
        self.locale = locale
    }
}

public struct CitationItem: Hashable, Codable, Sendable {
    public var itemID: UUID
    public var locator: String?
    public var prefix: String?
    public var suffix: String?
    public var suppressAuthor: Bool

    public init(
        itemID: UUID,
        locator: String? = nil,
        prefix: String? = nil,
        suffix: String? = nil,
        suppressAuthor: Bool = false
    ) {
        self.itemID = itemID
        self.locator = locator
        self.prefix = prefix
        self.suffix = suffix
        self.suppressAuthor = suppressAuthor
    }
}

public struct CitationCluster: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var items: [CitationItem]
    public var noteIndex: Int?

    public init(id: UUID = UUID(), items: [CitationItem], noteIndex: Int? = nil) {
        self.id = id
        self.items = items
        self.noteIndex = noteIndex
    }
}

public struct CitationRenderOptions: Hashable, Codable, Sendable {
    public var format: CitationOutputFormat
    public var includeLinks: Bool

    public init(format: CitationOutputFormat = .plainText, includeLinks: Bool = false) {
        self.format = format
        self.includeLinks = includeLinks
    }
}

public struct FormattedCitationCluster: Hashable, Codable, Sendable {
    public var clusterID: UUID
    public var text: String
    public var format: CitationOutputFormat

    public init(clusterID: UUID, text: String, format: CitationOutputFormat) {
        self.clusterID = clusterID
        self.text = text
        self.format = format
    }
}

public struct FormattedBibliography: Hashable, Codable, Sendable {
    public var entries: [String]
    public var format: CitationOutputFormat

    public init(entries: [String], format: CitationOutputFormat) {
        self.entries = entries
        self.format = format
    }
}
