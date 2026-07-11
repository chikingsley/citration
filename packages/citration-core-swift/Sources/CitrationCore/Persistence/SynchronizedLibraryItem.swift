import Foundation

// MARK: - SynchronizedLibraryItemIdentity

/// Stable identity for one item in one persisted library.
///
/// Zotero's object key is the synchronization identity. The app UUID remains
/// available for Citration's local relationships and migrated data.
public struct SynchronizedLibraryItemIdentity: Hashable, Sendable {
    // MARK: Lifecycle

    public init(libraryID: Int64, objectKey: String, appUUID: UUID) {
        self.libraryID = libraryID
        self.objectKey = objectKey
        self.appUUID = appUUID
    }

    // MARK: Public

    public let libraryID: Int64
    public let objectKey: String
    public let appUUID: UUID
}

// MARK: - SynchronizedLibraryItem

/// The library-facing item projection used by native clients.
///
/// `bibliographic` is the compatibility payload consumed by existing citation,
/// metadata, and relationship features. Identity and selection use the final
/// library and Zotero object identity instead of that payload's local UUID.
public struct SynchronizedLibraryItem: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        identity: SynchronizedLibraryItemIdentity,
        bibliographic: BCItem,
        projected: ZoteroProjectedItem,
        zoteroItemType: String,
        zoteroDate: String,
        publicationTitle: String,
        parentItemKey: String?
    ) {
        self.identity = identity
        self.bibliographic = bibliographic
        self.projected = projected
        self.zoteroItemType = zoteroItemType
        self.zoteroDate = zoteroDate
        self.publicationTitle = publicationTitle
        self.parentItemKey = parentItemKey
    }

    // MARK: Public

    public let identity: SynchronizedLibraryItemIdentity
    public var bibliographic: BCItem
    public let projected: ZoteroProjectedItem
    public let zoteroItemType: String
    public let zoteroDate: String
    public let publicationTitle: String
    public let parentItemKey: String?

    public var id: SynchronizedLibraryItemIdentity {
        identity
    }

    public var title: String {
        bibliographic.title
    }

    public var identifiers: [Identifier] {
        bibliographic.identifiers
    }

    public var doi: String? {
        bibliographic.doi
    }

    public var itemType: ItemType {
        bibliographic.itemType
    }

    public var creators: [Creator] {
        bibliographic.creators
    }

    public var publicationYear: Int? {
        bibliographic.publicationYear
    }

    public var tags: [String] {
        bibliographic.tags
    }

    public var createdAt: Date {
        bibliographic.createdAt
    }

    public var updatedAt: Date {
        bibliographic.updatedAt
    }
}

// MARK: - SynchronizedLibraryItemStoring

public protocol SynchronizedLibraryItemStoring: BCItemStore {
    func listLibraryItems() async -> [SynchronizedLibraryItem]
    func updateItemFields(
        identity: SynchronizedLibraryItemIdentity,
        updates: [ZoteroItemFieldUpdate]
    ) async throws -> SynchronizedLibraryItem
}
