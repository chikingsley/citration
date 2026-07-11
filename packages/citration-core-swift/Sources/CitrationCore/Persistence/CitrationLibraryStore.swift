import Foundation
import GRDB

// MARK: - CitrationLibraryStore

public actor CitrationLibraryStore:
    BCItemStore,
    SynchronizedLibraryItemStoring,
    LibraryAnnotationStoring,
    LibraryAttachmentStoring,
    LibraryCollectionStoring,
    LibraryNoteStoring,
    LibraryReaderProgressStoring,
    LibraryRelationshipStoring
{
    // MARK: Lifecycle

    public init(
        database: CitrationDatabase,
        attachmentsDirectory: URL,
        libraryIdentity: ZoteroLibraryIdentity = .init(type: "local", remoteID: 0),
        libraryName: String = "Local Library",
        initialItems: [BCItem] = [],
        fileManager: FileManager = .default
    ) throws {
        self.database = database
        self.attachmentsDirectory = attachmentsDirectory
        self.fileManager = fileManager
        let libraryID = try database.upsertLibrary(
            identity: libraryIdentity,
            name: libraryName
        )
        initialLibraryID = libraryID
        self.libraryID = libraryID
        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        for item in initialItems {
            let key = LegacyZoteroObjectFactory.itemKey(for: item.id)
            let object = try LegacyZoteroObjectFactory.itemObject(item, key: key, collectionKeys: [])
            try database.storeLocalItems([object], libraryID: libraryID)
            try database.databaseQueue.write { database in
                try database.execute(
                    sql: """
                    INSERT INTO app_object_identity (
                        library_id, object_kind, object_key, app_uuid, created_at, updated_at
                    ) VALUES (?, 'item', ?, ?, ?, ?)
                    """,
                    arguments: [
                        libraryID,
                        key,
                        item.id.uuidString,
                        item.createdAt.timeIntervalSince1970,
                        item.updatedAt.timeIntervalSince1970,
                    ]
                )
            }
        }
    }

    // MARK: Public

    /// The library selected when this store was created. Production clients can
    /// switch the same store after a connection is established without
    /// rebuilding every feature model around a second persistence path.
    public nonisolated let initialLibraryID: Int64

    public func selectLibrary(identity: ZoteroLibraryIdentity, name: String? = nil) throws -> Int64 {
        let selectedID = try database.upsertLibrary(identity: identity, name: name)
        libraryID = selectedID
        return selectedID
    }

    public func selectedLibraryID() -> Int64 {
        libraryID
    }

    // MARK: Internal

    let database: CitrationDatabase
    let attachmentsDirectory: URL
    let fileManager: FileManager
    var libraryID: Int64
}
