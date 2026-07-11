import Foundation
import GRDB

// MARK: - CitrationLibraryStore

public actor CitrationLibraryStore:
    BCItemStore,
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
        libraryID = try database.upsertLibrary(
            identity: libraryIdentity,
            name: libraryName
        )
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

    public nonisolated let libraryID: Int64

    // MARK: Internal

    let database: CitrationDatabase
    let attachmentsDirectory: URL
    let fileManager: FileManager
}
