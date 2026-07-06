import Foundation

// MARK: - CitationOutputFormat

public enum CitationOutputFormat: String, Codable, CaseIterable, Sendable {
    case plainText
    case markdown
    case html
}

// MARK: - CitationStyle

public struct CitationStyle: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(id: String, title: String, locale: String = "en-US") {
        self.id = id
        self.title = title
        self.locale = locale
    }

    // MARK: Public

    public var id: String
    public var title: String
    public var locale: String
}

// MARK: - CitationItem

public struct CitationItem: Hashable, Codable, Sendable {
    // MARK: Lifecycle

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

    // MARK: Public

    public var itemID: UUID
    public var locator: String?
    public var prefix: String?
    public var suffix: String?
    public var suppressAuthor: Bool
}

// MARK: - CitationCluster

public struct CitationCluster: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(id: UUID = UUID(), items: [CitationItem], noteIndex: Int? = nil) {
        self.id = id
        self.items = items
        self.noteIndex = noteIndex
    }

    // MARK: Public

    public var id: UUID
    public var items: [CitationItem]
    public var noteIndex: Int?
}

// MARK: - CitationRenderOptions

public struct CitationRenderOptions: Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(format: CitationOutputFormat = .plainText, includeLinks: Bool = false) {
        self.format = format
        self.includeLinks = includeLinks
    }

    // MARK: Public

    public var format: CitationOutputFormat
    public var includeLinks: Bool
}

// MARK: - FormattedCitationCluster

public struct FormattedCitationCluster: Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(clusterID: UUID, text: String, format: CitationOutputFormat) {
        self.clusterID = clusterID
        self.text = text
        self.format = format
    }

    // MARK: Public

    public var clusterID: UUID
    public var text: String
    public var format: CitationOutputFormat
}

// MARK: - FormattedBibliography

public struct FormattedBibliography: Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(entries: [String], format: CitationOutputFormat) {
        self.entries = entries
        self.format = format
    }

    // MARK: Public

    public var entries: [String]
    public var format: CitationOutputFormat
}
