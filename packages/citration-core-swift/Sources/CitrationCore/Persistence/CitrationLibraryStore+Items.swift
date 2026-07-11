import Foundation
import GRDB

extension CitrationLibraryStore {
    public func listItems() -> [BCItem] {
        do {
            return try fetchItems()
        } catch {
            fatalError("Failed to read the GRDB library: \(error)")
        }
    }

    public func upsert(_ item: BCItem) {
        do {
            try upsertItem(item)
        } catch {
            fatalError("Failed to write item \(item.id) to GRDB: \(error)")
        }
    }

    public func removeItem(id: UUID) {
        do {
            guard let key = try objectKey(for: id, kind: .item) else {
                return
            }
            try markDeleted(kind: .item, key: key)
        } catch {
            fatalError("Failed to remove item \(id) from GRDB: \(error)")
        }
    }

    private func fetchItems() throws -> [BCItem] {
        try database.databaseQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT item.*, identity.app_uuid,
                    (SELECT text_value FROM item_fields field
                     WHERE field.library_id = item.library_id AND field.item_key = item.item_key
                       AND field.field_name = 'dateAdded') AS date_added,
                    (SELECT text_value FROM item_fields field
                     WHERE field.library_id = item.library_id AND field.item_key = item.item_key
                       AND field.field_name = 'dateModified') AS date_modified
                FROM item_projections item
                JOIN app_object_identity identity
                  ON identity.library_id = item.library_id
                 AND identity.object_kind = 'item'
                 AND identity.object_key = item.item_key
                JOIN zotero_objects object
                  ON object.library_id = item.library_id
                 AND object.object_kind = 'item'
                 AND object.object_key = item.item_key
                WHERE item.library_id = ?
                  AND item.item_type NOT IN ('annotation', 'attachment', 'note')
                  AND object.is_deleted = 0
                ORDER BY date_modified DESC, item.title COLLATE NOCASE
                """,
                arguments: [libraryID]
            )
            return try rows.map { try Self.decodeItem(row: $0, database: database) }
        }
    }

    private func upsertItem(_ input: BCItem) throws {
        let existing = try fetchItems().first { $0.id == input.id }
        var item = input
        item.createdAt = existing?.createdAt ?? input.createdAt
        item.updatedAt = .now
        let key = try objectKey(for: item.id, kind: .item)
            ?? LegacyZoteroObjectFactory.itemKey(for: item.id)
        let collectionKeys = try database.databaseQueue.read { database in
            try String.fetchAll(
                database,
                sql: """
                SELECT collection_key FROM app_collection_memberships
                WHERE library_id = ? AND item_key = ? ORDER BY collection_key
                """,
                arguments: [libraryID, key]
            )
        }
        let object = try LegacyZoteroObjectFactory.itemObject(
            item,
            key: key,
            collectionKeys: collectionKeys
        )
        try database.storeLocalItems([object], libraryID: libraryID)
        try upsertIdentity(
            uuid: item.id,
            kind: .item,
            key: key,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }

    private static func decodeItem(row: Row, database: Database) throws -> BCItem {
        let libraryID: Int64 = row["library_id"]
        let key: String = row["item_key"]
        let uuidText: String = row["app_uuid"]
        guard let id = UUID(uuidString: uuidText) else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        return try BCItem(
            id: id,
            title: row["title"],
            identifiers: fetchIdentifiers(libraryID: libraryID, key: key, database: database),
            itemType: itemType(from: row["item_type"]),
            creators: fetchBCItemCreators(libraryID: libraryID, key: key, database: database),
            publicationYear: publicationYear(from: row["date_text"]),
            tags: fetchBCItemTags(libraryID: libraryID, key: key, database: database),
            createdAt: parseDate(row["date_added"]) ?? .distantPast,
            updatedAt: parseDate(row["date_modified"]) ?? .distantPast
        )
    }

    private static func fetchIdentifiers(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> [Identifier] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT identifier_type, identifier_value FROM item_identifiers
            WHERE library_id = ? AND item_key = ? ORDER BY position
            """,
            arguments: [libraryID, key]
        ).compactMap { row in
            let rawType: String = row["identifier_type"]
            let type: IdentifierType? = switch rawType {
            case "DOI": .doi
            case "ISBN": .isbn
            case "PMID": .pmid
            case "url": .url
            default: nil
            }
            return type.map { Identifier(type: $0, value: row["identifier_value"]) }
        }
    }

    private static func fetchBCItemCreators(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> [Creator] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT first_name, last_name, literal_name FROM item_creators
            WHERE library_id = ? AND item_key = ? ORDER BY position
            """,
            arguments: [libraryID, key]
        ).map { row in
            Creator(
                givenName: row["first_name"],
                familyName: row["last_name"],
                literalName: row["literal_name"]
            )
        }
    }

    private static func fetchBCItemTags(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> [String] {
        try String.fetchAll(
            database,
            sql: "SELECT tag FROM item_tags WHERE library_id = ? AND item_key = ? ORDER BY position",
            arguments: [libraryID, key]
        )
    }

    private static func itemType(from value: String) -> ItemType {
        switch value {
        case "book": .book
        case "preprint": .preprint
        case "thesis": .thesis
        case "dataset": .dataset
        case "webpage": .webpage
        case "journalArticle",
             "conferencePaper": .article
        default: .unknown
        }
    }

    private static func publicationYear(from value: String) -> Int? {
        value.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
    }

    static func parseDate(_ value: String?) -> Date? {
        value.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}
