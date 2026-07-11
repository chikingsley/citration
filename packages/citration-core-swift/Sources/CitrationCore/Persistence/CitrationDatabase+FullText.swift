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

// MARK: - LibrarySearchField

public enum LibrarySearchField: Sendable {
    case all
    case title
    case creator
    case tags
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

    /// Searches every indexed representation of a library item and resolves
    /// child note, attachment, annotation, full-text, and collection hits back
    /// to the owning top-level bibliographic item.
    func searchLibraryItemKeys(
        libraryID: Int64,
        query: String,
        field: LibrarySearchField = .all,
        limit: Int = 200
    ) throws -> [String] {
        guard let matchQuery = Self.librarySearchMatchQuery(query, field: field), limit > 0 else {
            return []
        }
        let includeCollections = field == .all ? 1 : 0
        return try databaseQueue.read { database in
            try String.fetchAll(
                database,
                sql: Self.libraryItemSearchSQL,
                arguments: [
                    matchQuery,
                    libraryID,
                    libraryID,
                    libraryID,
                    includeCollections,
                    libraryID,
                    limit,
                ]
            )
        }
    }

    private static func librarySearchMatchQuery(_ query: String, field: LibrarySearchField) -> String? {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { term in
                "\"\(term.replacingOccurrences(of: "\"", with: "\"\""))\"*"
            }
        guard !terms.isEmpty else {
            return nil
        }
        let expression = terms.joined(separator: " AND ")
        return switch field {
        case .all:
            expression
        case .title:
            "title : (\(expression))"
        case .creator:
            "creators : (\(expression))"
        case .tags:
            "tags : (\(expression))"
        }
    }

    private static let libraryItemSearchSQL = """
    WITH fts_hits AS (
        SELECT object_key, object_kind, bm25(library_search) AS score
        FROM library_search
        WHERE library_search MATCH ? AND library_id = ?
    ),
    item_hits AS (
        SELECT
            CASE
                WHEN item.item_type NOT IN ('attachment', 'annotation', 'note')
                    THEN item.item_key
                WHEN item.item_type = 'annotation'
                    THEN COALESCE(parent.parent_item_key, item.parent_item_key)
                ELSE item.parent_item_key
            END AS root_key,
            hit.score
        FROM fts_hits hit
        JOIN item_projections item
          ON hit.object_kind = 'item'
         AND item.library_id = ?
         AND item.item_key = hit.object_key
        LEFT JOIN item_projections parent
          ON parent.library_id = item.library_id
         AND parent.item_key = item.parent_item_key
    ),
    collection_hits AS (
        SELECT membership.item_key AS root_key, hit.score
        FROM fts_hits hit
        JOIN collection_items membership
          ON hit.object_kind = 'collection'
         AND membership.library_id = ?
         AND membership.collection_key = hit.object_key
        WHERE ? = 1
    ),
    ranked AS (
        SELECT root_key, score FROM item_hits WHERE root_key IS NOT NULL
        UNION ALL
        SELECT root_key, score FROM collection_hits
    )
    SELECT ranked.root_key
    FROM ranked
    JOIN item_projections root
      ON root.library_id = ? AND root.item_key = ranked.root_key
    WHERE root.item_type NOT IN ('attachment', 'annotation', 'note')
    GROUP BY ranked.root_key
    ORDER BY MIN(ranked.score), root.title COLLATE NOCASE
    LIMIT ?
    """
}
