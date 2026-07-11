import Foundation
import GRDB

extension CitrationLibraryStore {
    public func listItems() -> [BCItem] {
        listLibraryItems().map(\.bibliographic)
    }

    public func listLibraryItems() -> [SynchronizedLibraryItem] {
        do {
            return try fetchLibraryItems()
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

    public func updateItemFields(
        identity: SynchronizedLibraryItemIdentity,
        updates: [ZoteroItemFieldUpdate]
    ) throws -> SynchronizedLibraryItem {
        guard
            identity.libraryID == libraryID,
            try objectKey(for: identity.appUUID, kind: .item) == identity.objectKey
        else {
            throw ZoteroItemEditingError.identityMismatch
        }

        _ = try database.updateLocalItemFields(
            libraryID: libraryID,
            key: identity.objectKey,
            updates: updates
        )
        guard let updated = try fetchLibraryItems().first(where: { $0.identity == identity }) else {
            throw ZoteroItemEditingError.itemNotFound
        }
        return updated
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

    func fetchLibraryItems() throws -> [SynchronizedLibraryItem] {
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
            return try rows.map { try Self.decodeLibraryItem(row: $0, database: database) }
        }
    }

    private func upsertItem(_ input: BCItem) throws {
        let existing = try fetchLibraryItems().first { $0.identity.appUUID == input.id }
        var item = input
        item.createdAt = existing?.bibliographic.createdAt ?? input.createdAt
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
        let existingObject = try database.databaseQueue.read { database -> JSONValue? in
            guard
                let data = try Data.fetchOne(
                    database,
                    sql: """
                    SELECT current_json FROM zotero_objects
                    WHERE library_id = ? AND object_kind = 'item' AND object_key = ?
                    """,
                    arguments: [libraryID, key]
                )
            else {
                return nil
            }
            return try ZoteroJSON.decode(data)
        }
        let object = try LegacyZoteroObjectFactory.mergingItemObject(
            item,
            previous: existing?.bibliographic,
            key: key,
            collectionKeys: collectionKeys,
            existingObject: existingObject
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

    private static func decodeLibraryItem(row: Row, database: Database) throws -> SynchronizedLibraryItem {
        let libraryID: Int64 = row["library_id"]
        let key: String = row["item_key"]
        let uuidText: String = row["app_uuid"]
        guard let id = UUID(uuidString: uuidText) else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        let bibliographic = try BCItem(
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
        let projected = try ZoteroProjectedItem(
            key: key,
            itemType: row["item_type"],
            title: row["title"],
            abstractNote: row["abstract_note"],
            date: row["date_text"],
            publicationTitle: row["publication_title"],
            doi: row["doi"],
            isbn: row["isbn"],
            issn: row["issn"],
            url: row["url"],
            language: row["language"],
            rights: row["rights"],
            extra: row["extra"],
            fields: CitrationDatabase.fetchFields(libraryID: libraryID, key: key, database: database),
            identifiers: CitrationDatabase.fetchIdentifiers(libraryID: libraryID, key: key, database: database),
            parentItemKey: row["parent_item_key"],
            noteHTML: row["note_html"],
            creators: CitrationDatabase.fetchCreators(libraryID: libraryID, key: key, database: database),
            tags: CitrationDatabase.fetchTags(libraryID: libraryID, key: key, database: database),
            collectionKeys: CitrationDatabase.fetchCollectionKeys(
                libraryID: libraryID,
                key: key,
                database: database
            ),
            attachment: nil,
            annotation: nil
        )
        return SynchronizedLibraryItem(
            identity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: key,
                appUUID: id
            ),
            bibliographic: bibliographic,
            projected: projected,
            zoteroItemType: row["item_type"],
            zoteroDate: row["date_text"],
            publicationTitle: row["publication_title"],
            parentItemKey: row["parent_item_key"]
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
