import Foundation

// MARK: - ZoteroProjectedCreator

public struct ZoteroProjectedCreator: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        position: Int,
        creatorType: String,
        firstName: String?,
        lastName: String?,
        literalName: String?
    ) {
        self.position = position
        self.creatorType = creatorType
        self.firstName = firstName
        self.lastName = lastName
        self.literalName = literalName
    }

    // MARK: Public

    public let position: Int
    public let creatorType: String
    public let firstName: String?
    public let lastName: String?
    public let literalName: String?
}

// MARK: - ZoteroProjectedTag

public struct ZoteroProjectedTag: Hashable, Sendable {
    // MARK: Lifecycle

    public init(position: Int, value: String, type: Int?) {
        self.position = position
        self.value = value
        self.type = type
    }

    // MARK: Public

    public let position: Int
    public let value: String
    public let type: Int?
}

// MARK: - ZoteroProjectedAttachment

public struct ZoteroProjectedAttachment: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        linkMode: String,
        contentType: String,
        charset: String,
        filename: String,
        remoteURL: String,
        remoteMD5: String?,
        remoteMTime: Int64?
    ) {
        self.linkMode = linkMode
        self.contentType = contentType
        self.charset = charset
        self.filename = filename
        self.remoteURL = remoteURL
        self.remoteMD5 = remoteMD5
        self.remoteMTime = remoteMTime
    }

    // MARK: Public

    public let linkMode: String
    public let contentType: String
    public let charset: String
    public let filename: String
    public let remoteURL: String
    public let remoteMD5: String?
    public let remoteMTime: Int64?
}

// MARK: - ZoteroProjectedAnnotation

public struct ZoteroProjectedAnnotation: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        type: String,
        color: String,
        pageLabel: String,
        sortIndex: String,
        text: String,
        comment: String,
        positionJSON: String
    ) {
        self.type = type
        self.color = color
        self.pageLabel = pageLabel
        self.sortIndex = sortIndex
        self.text = text
        self.comment = comment
        self.positionJSON = positionJSON
    }

    // MARK: Public

    public let type: String
    public let color: String
    public let pageLabel: String
    public let sortIndex: String
    public let text: String
    public let comment: String
    public let positionJSON: String
}

// MARK: - ZoteroProjectedIdentifier

public struct ZoteroProjectedIdentifier: Hashable, Sendable {
    // MARK: Lifecycle

    public init(type: String, value: String) {
        self.type = type
        self.value = value
    }

    // MARK: Public

    public let type: String
    public let value: String
}

// MARK: - ZoteroProjectedItem

public struct ZoteroProjectedItem: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        key: String,
        itemType: String,
        title: String,
        abstractNote: String,
        date: String,
        publicationTitle: String,
        doi: String,
        isbn: String,
        issn: String,
        url: String,
        language: String,
        rights: String,
        extra: String,
        fields: [String: JSONValue],
        identifiers: [ZoteroProjectedIdentifier],
        parentItemKey: String?,
        noteHTML: String?,
        creators: [ZoteroProjectedCreator],
        tags: [ZoteroProjectedTag],
        collectionKeys: [String],
        attachment: ZoteroProjectedAttachment?,
        annotation: ZoteroProjectedAnnotation?
    ) {
        self.key = key
        self.itemType = itemType
        self.title = title
        self.abstractNote = abstractNote
        self.date = date
        self.publicationTitle = publicationTitle
        self.doi = doi
        self.isbn = isbn
        self.issn = issn
        self.url = url
        self.language = language
        self.rights = rights
        self.extra = extra
        self.fields = fields
        self.identifiers = identifiers
        self.parentItemKey = parentItemKey
        self.noteHTML = noteHTML
        self.creators = creators
        self.tags = tags
        self.collectionKeys = collectionKeys
        self.attachment = attachment
        self.annotation = annotation
    }

    // MARK: Public

    public let key: String
    public let itemType: String
    public let title: String
    public let abstractNote: String
    public let date: String
    public let publicationTitle: String
    public let doi: String
    public let isbn: String
    public let issn: String
    public let url: String
    public let language: String
    public let rights: String
    public let extra: String
    public let fields: [String: JSONValue]
    public let identifiers: [ZoteroProjectedIdentifier]
    public let parentItemKey: String?
    public let noteHTML: String?
    public let creators: [ZoteroProjectedCreator]
    public let tags: [ZoteroProjectedTag]
    public let collectionKeys: [String]
    public let attachment: ZoteroProjectedAttachment?
    public let annotation: ZoteroProjectedAnnotation?
}

// MARK: - ZoteroLibraryItemSummary

public struct ZoteroLibraryItemSummary: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        key: String,
        itemType: String,
        title: String,
        date: String,
        publicationTitle: String,
        parentItemKey: String?
    ) {
        self.key = key
        self.itemType = itemType
        self.title = title
        self.date = date
        self.publicationTitle = publicationTitle
        self.parentItemKey = parentItemKey
    }

    // MARK: Public

    public let key: String
    public let itemType: String
    public let title: String
    public let date: String
    public let publicationTitle: String
    public let parentItemKey: String?
}
