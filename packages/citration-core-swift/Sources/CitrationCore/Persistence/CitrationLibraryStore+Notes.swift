import Foundation
import GRDB

public extension CitrationLibraryStore {
    func listNotes(itemID: UUID?) throws -> [LibraryNote] {
        try listSynchronizedNotes(itemID: itemID).map { note in
            LibraryNote(
                id: note.identity.appUUID,
                itemID: note.parentIdentity.appUUID,
                text: note.html,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt
            )
        }
    }

    func listSynchronizedNotes(itemID: UUID?) throws -> [SynchronizedLibraryNote] {
        try database.databaseQueue.read { database in
            var arguments: StatementArguments = [libraryID]
            var itemClause = ""
            if let itemID {
                itemClause = "AND parent_identity.app_uuid = ?"
                arguments += [itemID.uuidString]
            }
            return try Row.fetchAll(
                database,
                sql: """
                SELECT note.library_id, note.item_key, note.note_html,
                    identity.app_uuid, parent_identity.app_uuid AS parent_uuid,
                    note.parent_item_key, object.object_version, object.sync_state,
                    (SELECT text_value FROM item_fields field
                     WHERE field.library_id = note.library_id AND field.item_key = note.item_key
                       AND field.field_name = 'dateAdded') AS date_added,
                    (SELECT text_value FROM item_fields field
                     WHERE field.library_id = note.library_id AND field.item_key = note.item_key
                       AND field.field_name = 'dateModified') AS date_modified
                FROM item_projections note
                JOIN app_object_identity identity
                  ON identity.library_id = note.library_id
                 AND identity.object_key = note.item_key
                JOIN app_object_identity parent_identity
                  ON parent_identity.library_id = note.library_id
                 AND parent_identity.object_key = note.parent_item_key
                JOIN zotero_objects object
                  ON object.library_id = note.library_id
                 AND object.object_kind = 'item'
                 AND object.object_key = note.item_key
                WHERE note.library_id = ? AND note.item_type = 'note' \(itemClause)
                ORDER BY date_modified DESC
                """,
                arguments: arguments
            ).map { row in
                try Self.decodeSynchronizedNote(row, database: database)
            }
        }
    }

    func upsert(_ input: LibraryNote) throws -> LibraryNote {
        let existing = try listNotes(itemID: input.itemID).first { $0.id == input.id }
        var note = input
        note.text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        note.createdAt = existing?.createdAt ?? input.createdAt
        note.updatedAt = .now
        guard let parentKey = try objectKey(for: note.itemID, kind: .item) else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        let key = try objectKey(for: note.id, kind: .item)
            ?? LegacyZoteroObjectFactory.noteKey(for: note.id)
        let object = try LegacyZoteroObjectFactory.noteObject(note, key: key, parentKey: parentKey)
        try database.storeLocalItems([object], libraryID: libraryID)
        try upsertIdentity(
            uuid: note.id,
            kind: .item,
            key: key,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt
        )
        return try listNotes(itemID: note.itemID).first { $0.id == note.id } ?? note
    }

    func remove(id: UUID) throws {
        if let key = try objectKey(for: id, kind: .item) {
            try markDeleted(kind: .item, key: key)
            return
        }
        try database.databaseQueue.write { database in
            try database.execute(
                sql: "DELETE FROM app_relationships WHERE library_id = ? AND relationship_id = ?",
                arguments: [libraryID, id.uuidString]
            )
        }
    }

    func removeNotes(itemIDs: [UUID]) throws {
        for itemID in Set(itemIDs) {
            for note in try listNotes(itemID: itemID) {
                try remove(id: note.id)
            }
        }
    }

    private static func decodeSynchronizedNote(_ row: Row, database: Database) throws -> SynchronizedLibraryNote {
        let libraryID: Int64 = row["library_id"]
        let itemKey: String = row["item_key"]
        let parentItemKey: String = row["parent_item_key"]
        let idText: String = row["app_uuid"]
        let parentText: String = row["parent_uuid"]
        guard let id = UUID(uuidString: idText), let itemID = UUID(uuidString: parentText) else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        let syncStateValue: String = row["sync_state"]
        guard let syncState = ZoteroSyncState(rawValue: syncStateValue) else {
            throw CitrationDatabaseError.unknownSyncState(syncStateValue)
        }
        return try SynchronizedLibraryNote(
            identity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: itemKey,
                appUUID: id
            ),
            parentIdentity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: parentItemKey,
                appUUID: itemID
            ),
            version: row["object_version"],
            syncState: syncState,
            html: row["note_html"],
            tags: CitrationDatabase.fetchTags(libraryID: libraryID, key: itemKey, database: database),
            createdAt: parseDate(row["date_added"]) ?? .distantPast,
            updatedAt: parseDate(row["date_modified"]) ?? .distantPast
        )
    }
}
