import Foundation

// MARK: - SynchronizedLibraryAnnotationContext

public struct SynchronizedLibraryAnnotationContext: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        parentAttachmentIdentity: SynchronizedLibraryItemIdentity,
        bibliographicItemIdentity: SynchronizedLibraryItemIdentity
    ) {
        self.parentAttachmentIdentity = parentAttachmentIdentity
        self.bibliographicItemIdentity = bibliographicItemIdentity
    }

    // MARK: Public

    public let parentAttachmentIdentity: SynchronizedLibraryItemIdentity
    public let bibliographicItemIdentity: SynchronizedLibraryItemIdentity
}

// MARK: - SynchronizedLibraryAnnotationDraft

/// A complete, Zotero-compatible annotation created against an existing attachment.
public struct SynchronizedLibraryAnnotationDraft: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        parentAttachmentIdentity: SynchronizedLibraryItemIdentity,
        bibliographicItemIdentity: SynchronizedLibraryItemIdentity,
        kind: AnnotationKind,
        color: AnnotationColor,
        pageLabel: String,
        sortIndex: String,
        text: String,
        comment: String,
        positionJSON: String,
        tags: [ZoteroProjectedTag] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.parentAttachmentIdentity = parentAttachmentIdentity
        self.bibliographicItemIdentity = bibliographicItemIdentity
        self.kind = kind
        self.color = color
        self.pageLabel = pageLabel
        self.sortIndex = sortIndex
        self.text = text
        self.comment = comment
        self.positionJSON = positionJSON
        self.tags = tags
        self.createdAt = createdAt
    }

    // MARK: Public

    public let id: UUID
    public let parentAttachmentIdentity: SynchronizedLibraryItemIdentity
    public let bibliographicItemIdentity: SynchronizedLibraryItemIdentity
    public let kind: AnnotationKind
    public let color: AnnotationColor
    public let pageLabel: String
    public let sortIndex: String
    public let text: String
    public let comment: String
    public let positionJSON: String
    public let tags: [ZoteroProjectedTag]
    public let createdAt: Date
}

// MARK: - SynchronizedLibraryAnnotationUpdate

/// Editable annotation fields. Identity, selected text, geometry, ordering, dates,
/// versions, relations, and unknown Zotero fields remain untouched.
public struct SynchronizedLibraryAnnotationUpdate: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        identity: SynchronizedLibraryItemIdentity,
        kind: AnnotationKind,
        color: AnnotationColor,
        comment: String,
        tags: [ZoteroProjectedTag]
    ) {
        self.identity = identity
        self.kind = kind
        self.color = color
        self.comment = comment
        self.tags = tags
    }

    // MARK: Public

    public let identity: SynchronizedLibraryItemIdentity
    public let kind: AnnotationKind
    public let color: AnnotationColor
    public let comment: String
    public let tags: [ZoteroProjectedTag]
}

// MARK: - AnnotationEditingError

public enum AnnotationEditingError: Error, Equatable, Sendable {
    case attachmentMismatch
    case duplicateIdentity
    case identityMismatch
    case invalidAnnotationType
    case invalidPosition
    case itemNotFound
}

public extension AnnotationColor {
    var zoteroHex: String {
        switch self {
        case .yellow: "#ffd400"
        case .green: "#5fb236"
        case .blue: "#2ea8e5"
        case .pink: "#e56eee"
        case .purple: "#a28ae5"
        }
    }
}
