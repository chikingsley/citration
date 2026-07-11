import Foundation
import GRDB

// MARK: - ZoteroObjectCount

public struct ZoteroObjectCount: Hashable, Sendable {
    public let kind: String
    public let count: Int
}

// MARK: - ZoteroPreservedObjectSummary

public struct ZoteroPreservedObjectSummary: Hashable, Identifiable, Sendable {
    public let kind: String
    public let key: String
    public let type: String?
    public let version: Int64
    public let syncState: ZoteroSyncState

    public var id: String {
        "\(kind):\(key)"
    }
}

// MARK: - ZoteroAttachmentStateSummary

public struct ZoteroAttachmentStateSummary: Hashable, Identifiable, Sendable {
    public let key: String
    public let parentKey: String?
    public let fileName: String
    public let contentType: String
    public let cacheState: String
    public let localPath: String?
    public let fullTextVersion: Int64?
    public let indexedPages: Int?
    public let totalPages: Int?

    public var id: String {
        key
    }
}

// MARK: - ZoteroSettingSummary

public struct ZoteroSettingSummary: Hashable, Identifiable, Sendable {
    public let key: String
    public let version: Int64
    public let value: JSONValue

    public var id: String {
        key
    }
}

// MARK: - ZoteroLibraryPreservationSnapshot

public struct ZoteroLibraryPreservationSnapshot: Hashable, Sendable {
    public let objectCounts: [ZoteroObjectCount]
    public let collectionCount: Int
    public let tagCount: Int
    public let fullTextCount: Int
    public let deletedObjects: [ZoteroPreservedObjectSummary]
    public let attachments: [ZoteroAttachmentStateSummary]
    public let settings: [ZoteroSettingSummary]
    public let unsupportedObjects: [ZoteroPreservedObjectSummary]
}

public extension CitrationDatabase {
    func libraryPreservationSnapshot(libraryID: Int64) throws -> ZoteroLibraryPreservationSnapshot {
        try databaseQueue.read { database in
            let objectCounts = try Row.fetchAll(
                database,
                sql: """
                SELECT object_kind, COUNT(*) AS object_count
                FROM zotero_objects WHERE library_id = ? AND is_deleted = 0
                GROUP BY object_kind ORDER BY object_kind
                """,
                arguments: [libraryID]
            ).map { row in
                ZoteroObjectCount(kind: row["object_kind"], count: row["object_count"])
            }
            return try ZoteroLibraryPreservationSnapshot(
                objectCounts: objectCounts,
                collectionCount: Self.preservationCount(database, table: "collection_projections", libraryID: libraryID),
                tagCount: Self.distinctTagCount(database: database, libraryID: libraryID),
                fullTextCount: Self.preservationCount(database, table: "fulltext_content", libraryID: libraryID),
                deletedObjects: Self.preservedObjects(database: database, libraryID: libraryID, deleted: true),
                attachments: Self.attachmentStates(database: database, libraryID: libraryID),
                settings: Self.settingSummaries(database: database, libraryID: libraryID),
                unsupportedObjects: Self.unsupportedObjects(database: database, libraryID: libraryID)
            )
        }
    }

    private static func distinctTagCount(database: Database, libraryID: Int64) throws -> Int {
        try Int.fetchOne(
            database,
            sql: "SELECT COUNT(DISTINCT tag) FROM item_tags WHERE library_id = ?",
            arguments: [libraryID]
        ) ?? 0
    }

    private static func preservationCount(_ database: Database, table: String, libraryID: Int64) throws -> Int {
        try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM \(table) WHERE library_id = ?",
            arguments: [libraryID]
        ) ?? 0
    }

    private static func preservedObjects(
        database: Database,
        libraryID: Int64,
        deleted: Bool
    ) throws -> [ZoteroPreservedObjectSummary] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT object_kind, object_key, object_type, object_version, sync_state
            FROM zotero_objects WHERE library_id = ? AND is_deleted = ?
            ORDER BY object_kind, object_key
            """,
            arguments: [libraryID, deleted]
        ).map(preservedObject)
    }

    private static func unsupportedObjects(
        database: Database,
        libraryID: Int64
    ) throws -> [ZoteroPreservedObjectSummary] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT object_kind, object_key, object_type, object_version, sync_state
            FROM zotero_objects object
            WHERE library_id = ? AND is_deleted = 0 AND (
              object_kind NOT IN ('collection', 'fulltext', 'item', 'search', 'setting')
              OR (object_kind = 'item' AND NOT EXISTS (
                SELECT 1 FROM item_projections projection
                WHERE projection.library_id = object.library_id
                  AND projection.item_key = object.object_key
              ))
            )
            ORDER BY object_kind, object_key
            """,
            arguments: [libraryID]
        ).map(preservedObject)
    }

    private static func preservedObject(_ row: Row) throws -> ZoteroPreservedObjectSummary {
        let state: String = row["sync_state"]
        guard let syncState = ZoteroSyncState(rawValue: state) else {
            throw CitrationDatabaseError.unknownSyncState(state)
        }
        return ZoteroPreservedObjectSummary(
            kind: row["object_kind"],
            key: row["object_key"],
            type: row["object_type"],
            version: row["object_version"],
            syncState: syncState
        )
    }

    private static func attachmentStates(database: Database, libraryID: Int64) throws -> [ZoteroAttachmentStateSummary] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT attachment.item_key, attachment.parent_item_key, attachment.filename,
                   attachment.content_type, attachment.cache_state, attachment.local_path,
                   fulltext.object_version, fulltext.indexed_pages, fulltext.total_pages
            FROM attachment_projections attachment
            LEFT JOIN fulltext_content fulltext
              ON fulltext.library_id = attachment.library_id AND fulltext.item_key = attachment.item_key
            WHERE attachment.library_id = ? ORDER BY attachment.filename COLLATE NOCASE, attachment.item_key
            """,
            arguments: [libraryID]
        ).map { row in
            ZoteroAttachmentStateSummary(
                key: row["item_key"],
                parentKey: row["parent_item_key"],
                fileName: row["filename"],
                contentType: row["content_type"],
                cacheState: row["cache_state"],
                localPath: row["local_path"],
                fullTextVersion: row["object_version"],
                indexedPages: row["indexed_pages"],
                totalPages: row["total_pages"]
            )
        }
    }

    private static func settingSummaries(database: Database, libraryID: Int64) throws -> [ZoteroSettingSummary] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT object_key, object_version, current_json FROM zotero_objects
            WHERE library_id = ? AND object_kind = 'setting' AND is_deleted = 0
            ORDER BY object_key
            """,
            arguments: [libraryID]
        ).map { row in
            let data: Data = row["current_json"]
            return try ZoteroSettingSummary(
                key: row["object_key"],
                version: row["object_version"],
                value: ZoteroJSON.decode(data)
            )
        }
    }
}
