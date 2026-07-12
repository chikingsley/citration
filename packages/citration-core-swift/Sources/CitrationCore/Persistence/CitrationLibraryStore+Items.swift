import Foundation
import GRDB

public extension CitrationLibraryStore {
    func listItems() -> [BCItem] {
        listLibraryItems().map(\.bibliographic)
    }

    func listLibraryItems() -> [SynchronizedLibraryItem] {
        do {
            return try fetchLibraryItems()
        } catch {
            fatalError("Failed to read the GRDB library: \(error)")
        }
    }

    func upsert(_ item: BCItem) {
        do {
            try upsertItem(item)
        } catch {
            fatalError("Failed to write item \(item.id) to GRDB: \(error)")
        }
    }

    func updateItemFields(
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

    func convertItemType(
        identity: SynchronizedLibraryItemIdentity,
        sourceSchema: ZoteroItemEditingSchema,
        targetSchema: ZoteroItemEditingSchema
    ) throws -> SynchronizedLibraryItem {
        guard
            identity.libraryID == libraryID,
            try objectKey(for: identity.appUUID, kind: .item) == identity.objectKey
        else {
            throw ZoteroItemEditingError.identityMismatch
        }

        _ = try database.convertLocalItemType(
            libraryID: libraryID,
            key: identity.objectKey,
            sourceSchema: sourceSchema,
            targetSchema: targetSchema
        )
        guard let updated = try fetchLibraryItems().first(where: { $0.identity == identity }) else {
            throw ZoteroItemEditingError.itemNotFound
        }
        return updated
    }

    func removeItem(id: UUID) {
        do {
            guard let key = try objectKey(for: id, kind: .item) else {
                return
            }
            try markDeleted(kind: .item, key: key)
        } catch {
            fatalError("Failed to remove item \(id) from GRDB: \(error)")
        }
    }

    internal func fetchLibraryItems() throws -> [SynchronizedLibraryItem] {
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
            let projectionData = try LibraryItemProjectionData.fetch(libraryID: libraryID, database: database)
            let dateFormatter = ISO8601DateFormatter()
            return try rows.map {
                try Self.decodeLibraryItem(
                    row: $0,
                    projectionData: projectionData,
                    dateFormatter: dateFormatter
                )
            }
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

    private static func decodeLibraryItem(
        row: Row,
        projectionData: LibraryItemProjectionData,
        dateFormatter: ISO8601DateFormatter
    ) throws -> SynchronizedLibraryItem {
        let libraryID: Int64 = row["library_id"]
        let key: String = row["item_key"]
        let uuidText: String = row["app_uuid"]
        guard let id = UUID(uuidString: uuidText) else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        let projectedIdentifiers = projectionData.identifiers[key, default: []]
        let projectedCreators = projectionData.creators[key, default: []]
        let projectedTags = projectionData.tags[key, default: []]
        let bibliographic = makeBibliographicItem(
            row: row,
            id: id,
            identifiers: projectedIdentifiers,
            creators: projectedCreators,
            tags: projectedTags,
            dateFormatter: dateFormatter
        )
        let projected = makeProjectedItem(
            row: row,
            key: key,
            identifiers: projectedIdentifiers,
            creators: projectedCreators,
            tags: projectedTags,
            projectionData: projectionData
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

    private static func makeBibliographicItem(
        row: Row,
        id: UUID,
        identifiers: [ZoteroProjectedIdentifier],
        creators: [ZoteroProjectedCreator],
        tags: [ZoteroProjectedTag],
        dateFormatter: ISO8601DateFormatter
    ) -> BCItem {
        BCItem(
            id: id,
            title: row["title"],
            identifiers: bibliographicIdentifiers(identifiers),
            itemType: itemType(from: row["item_type"]),
            creators: creators.map { creator in
                Creator(
                    givenName: creator.firstName,
                    familyName: creator.lastName,
                    literalName: creator.literalName
                )
            },
            publicationYear: publicationYear(from: row["date_text"]),
            tags: tags.map(\.value),
            createdAt: parseDate(row["date_added"], using: dateFormatter) ?? .distantPast,
            updatedAt: parseDate(row["date_modified"], using: dateFormatter) ?? .distantPast
        )
    }

    private static func makeProjectedItem(
        row: Row,
        key: String,
        identifiers: [ZoteroProjectedIdentifier],
        creators: [ZoteroProjectedCreator],
        tags: [ZoteroProjectedTag],
        projectionData: LibraryItemProjectionData
    ) -> ZoteroProjectedItem {
        ZoteroProjectedItem(
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
            fields: [:],
            identifiers: identifiers,
            parentItemKey: row["parent_item_key"],
            noteHTML: row["note_html"],
            creators: creators,
            tags: tags,
            collectionKeys: projectionData.collectionKeys[key, default: []],
            attachment: nil,
            annotation: nil
        )
    }

    private static func bibliographicIdentifiers(
        _ identifiers: [ZoteroProjectedIdentifier]
    ) -> [Identifier] {
        identifiers.compactMap { identifier in
            let type: IdentifierType? = switch identifier.type {
            case "DOI": .doi
            case "ISBN": .isbn
            case "PMID": .pmid
            case "url": .url
            default: nil
            }
            return type.map { Identifier(type: $0, value: identifier.value) }
        }
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

    internal static func parseDate(_ value: String?) -> Date? {
        value.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    private static func parseDate(
        _ value: String?,
        using formatter: ISO8601DateFormatter
    ) -> Date? {
        value.flatMap(formatter.date(from:))
    }
}

// MARK: - LibraryItemProjectionData

private struct LibraryItemProjectionData {
    // MARK: Internal

    let identifiers: [String: [ZoteroProjectedIdentifier]]
    let creators: [String: [ZoteroProjectedCreator]]
    let tags: [String: [ZoteroProjectedTag]]
    let collectionKeys: [String: [String]]

    static func fetch(libraryID: Int64, database: Database) throws -> Self {
        try Self(
            identifiers: fetchIdentifiers(libraryID: libraryID, database: database),
            creators: fetchCreators(libraryID: libraryID, database: database),
            tags: fetchTags(libraryID: libraryID, database: database),
            collectionKeys: fetchCollectionKeys(libraryID: libraryID, database: database)
        )
    }

    // MARK: Private

    private static func fetchIdentifiers(
        libraryID: Int64,
        database: Database
    ) throws -> [String: [ZoteroProjectedIdentifier]] {
        var identifiers = [String: [ZoteroProjectedIdentifier]]()
        for row in try Row.fetchAll(
            database,
            sql: """
            SELECT item_key, identifier_type, identifier_value FROM item_identifiers
            WHERE library_id = ? ORDER BY item_key, position
            """,
            arguments: [libraryID]
        ) {
            let key: String = row["item_key"]
            identifiers[key, default: []].append(
                ZoteroProjectedIdentifier(type: row["identifier_type"], value: row["identifier_value"])
            )
        }
        return identifiers
    }

    private static func fetchCreators(
        libraryID: Int64,
        database: Database
    ) throws -> [String: [ZoteroProjectedCreator]] {
        var creators = [String: [ZoteroProjectedCreator]]()
        for row in try Row.fetchAll(
            database,
            sql: """
            SELECT item_key, position, creator_type, first_name, last_name, literal_name
            FROM item_creators WHERE library_id = ? ORDER BY item_key, position
            """,
            arguments: [libraryID]
        ) {
            let key: String = row["item_key"]
            creators[key, default: []].append(
                ZoteroProjectedCreator(
                    position: row["position"],
                    creatorType: row["creator_type"],
                    firstName: row["first_name"],
                    lastName: row["last_name"],
                    literalName: row["literal_name"]
                )
            )
        }
        return creators
    }

    private static func fetchTags(
        libraryID: Int64,
        database: Database
    ) throws -> [String: [ZoteroProjectedTag]] {
        var tags = [String: [ZoteroProjectedTag]]()
        for row in try Row.fetchAll(
            database,
            sql: """
            SELECT item_key, position, tag, tag_type FROM item_tags
            WHERE library_id = ? ORDER BY item_key, position
            """,
            arguments: [libraryID]
        ) {
            let key: String = row["item_key"]
            tags[key, default: []].append(
                ZoteroProjectedTag(position: row["position"], value: row["tag"], type: row["tag_type"])
            )
        }
        return tags
    }

    private static func fetchCollectionKeys(
        libraryID: Int64,
        database: Database
    ) throws -> [String: [String]] {
        var collectionKeys = [String: [String]]()
        for row in try Row.fetchAll(
            database,
            sql: """
            SELECT item_key, collection_key FROM collection_items
            WHERE library_id = ? ORDER BY item_key, position
            """,
            arguments: [libraryID]
        ) {
            let key: String = row["item_key"]
            let collectionKey: String = row["collection_key"]
            collectionKeys[key, default: []].append(collectionKey)
        }
        return collectionKeys
    }
}
