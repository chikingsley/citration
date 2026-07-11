import Foundation
import GRDB

// MARK: - ZoteroFullTextContent

public struct ZoteroFullTextContent: Hashable, Sendable {
    // MARK: Lifecycle

    public init(itemKey: String, version: Int64, content: String, indexedPages: Int?, totalPages: Int?) {
        self.itemKey = itemKey
        self.version = version
        self.content = content
        self.indexedPages = indexedPages
        self.totalPages = totalPages
    }

    // MARK: Public

    public let itemKey: String
    public let version: Int64
    public let content: String
    public let indexedPages: Int?
    public let totalPages: Int?
}

public extension CitrationDatabase {
    func storeRemoteFullText(
        itemKey: String,
        version: Int64,
        response: JSONValue,
        libraryID: Int64
    ) throws {
        guard !itemKey.isEmpty, let data = response.objectValue else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        let content = Self.string("content", in: data)
        let indexedPages = data["indexedPages"]?.integerValue.map(Int.init)
        let totalPages = data["totalPages"]?.integerValue.map(Int.init)
        let storedObject = ZoteroStoredObject(
            kind: .fulltext,
            key: itemKey,
            version: version,
            current: response
        )

        try databaseQueue.write { database in
            try Self.upsert(object: storedObject, libraryID: libraryID, database: database)
            try database.execute(
                sql: """
                INSERT INTO fulltext_content (
                    library_id, item_key, object_version, content,
                    indexed_pages, total_pages, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, unixepoch('subsec'))
                ON CONFLICT (library_id, item_key) DO UPDATE SET
                    object_version = excluded.object_version,
                    content = excluded.content,
                    indexed_pages = excluded.indexed_pages,
                    total_pages = excluded.total_pages,
                    updated_at = excluded.updated_at
                """,
                arguments: [libraryID, itemKey, version, content, indexedPages, totalPages]
            )
            try database.execute(
                sql: """
                UPDATE library_search SET fulltext = ?
                WHERE library_id = ? AND object_key = ? AND object_kind = 'item'
                """,
                arguments: [content, libraryID, itemKey]
            )
            if database.changesCount == 0 {
                try database.execute(
                    sql: """
                    INSERT INTO library_search (library_id, object_key, object_kind, fulltext)
                    VALUES (?, ?, 'item', ?)
                    """,
                    arguments: [libraryID, itemKey, content]
                )
            }
        }
    }

    func fetchFullText(libraryID: Int64, itemKey: String) throws -> ZoteroFullTextContent? {
        try databaseQueue.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: """
                    SELECT object_version, content, indexed_pages, total_pages
                    FROM fulltext_content WHERE library_id = ? AND item_key = ?
                    """,
                    arguments: [libraryID, itemKey]
                )
            else {
                return nil
            }
            return ZoteroFullTextContent(
                itemKey: itemKey,
                version: row["object_version"],
                content: row["content"],
                indexedPages: row["indexed_pages"],
                totalPages: row["total_pages"]
            )
        }
    }

    func searchObjectKeys(libraryID: Int64, query: String, limit: Int = 50) throws -> [String] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, limit > 0 else {
            return []
        }
        return try databaseQueue.read { database in
            try String.fetchAll(
                database,
                sql: """
                SELECT object_key FROM library_search
                WHERE library_search MATCH ? AND library_id = ?
                ORDER BY rank LIMIT ?
                """,
                arguments: [query, libraryID, limit]
            )
        }
    }
}
