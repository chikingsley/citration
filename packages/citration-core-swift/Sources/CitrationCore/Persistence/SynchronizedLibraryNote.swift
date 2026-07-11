import Foundation

// MARK: - SynchronizedLibraryNote

public struct SynchronizedLibraryNote: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        identity: SynchronizedLibraryItemIdentity,
        parentIdentity: SynchronizedLibraryItemIdentity,
        version: Int64,
        syncState: ZoteroSyncState,
        html: String,
        tags: [ZoteroProjectedTag],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.identity = identity
        self.parentIdentity = parentIdentity
        self.version = version
        self.syncState = syncState
        self.html = html
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: Public

    public let identity: SynchronizedLibraryItemIdentity
    public let parentIdentity: SynchronizedLibraryItemIdentity
    public let version: Int64
    public let syncState: ZoteroSyncState
    public let html: String
    public let tags: [ZoteroProjectedTag]
    public let createdAt: Date
    public let updatedAt: Date

    public var id: SynchronizedLibraryItemIdentity {
        identity
    }
}

// MARK: - SynchronizedLibraryNoteStoring

public protocol SynchronizedLibraryNoteStoring: LibraryNoteStoring {
    func listSynchronizedNotes(itemID: UUID?) async throws -> [SynchronizedLibraryNote]
}
