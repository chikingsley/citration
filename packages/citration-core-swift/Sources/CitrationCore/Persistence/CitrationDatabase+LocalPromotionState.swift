import GRDB

extension CitrationDatabase {
    static func copyLocalState(
        keyMap: [String: String],
        sourceLibraryID: Int64,
        targetLibraryID: Int64,
        database: Database
    ) throws {
        try copyMemberships(
            keyMap: keyMap,
            sourceLibraryID: sourceLibraryID,
            targetLibraryID: targetLibraryID,
            database: database
        )
        try copyReaderState(
            keyMap: keyMap,
            sourceLibraryID: sourceLibraryID,
            targetLibraryID: targetLibraryID,
            database: database
        )
        try copyRelationships(
            keyMap: keyMap,
            sourceLibraryID: sourceLibraryID,
            targetLibraryID: targetLibraryID,
            database: database
        )
        try copyAttachmentCache(
            keyMap: keyMap,
            sourceLibraryID: sourceLibraryID,
            targetLibraryID: targetLibraryID,
            database: database
        )
    }

    private static func copyMemberships(
        keyMap: [String: String],
        sourceLibraryID: Int64,
        targetLibraryID: Int64,
        database: Database
    ) throws {
        for row in try Row.fetchAll(
            database,
            sql: "SELECT * FROM app_collection_memberships WHERE library_id = ?",
            arguments: [sourceLibraryID]
        ) {
            let sourceCollection: String = row["collection_key"]
            let sourceItem: String = row["item_key"]
            guard let collection = keyMap[sourceCollection], let item = keyMap[sourceItem] else {
                continue
            }
            try database.execute(
                sql: """
                INSERT INTO app_collection_memberships (
                    library_id, collection_key, item_key, membership_uuid, created_at
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (library_id, collection_key, item_key) DO NOTHING
                """,
                arguments: [targetLibraryID, collection, item, row["membership_uuid"], row["created_at"]]
            )
        }
    }

    private static func copyReaderState(
        keyMap: [String: String],
        sourceLibraryID: Int64,
        targetLibraryID: Int64,
        database: Database
    ) throws {
        for row in try Row.fetchAll(
            database,
            sql: "SELECT * FROM reader_state WHERE library_id = ?",
            arguments: [sourceLibraryID]
        ) {
            let sourceKey: String = row["item_key"]
            guard let targetKey = keyMap[sourceKey] else {
                continue
            }
            try database.execute(
                sql: """
                INSERT INTO reader_state (
                    library_id, item_key, locator_json, fraction_complete, selected_page, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT (library_id, item_key) DO UPDATE SET
                    locator_json = excluded.locator_json,
                    fraction_complete = excluded.fraction_complete,
                    selected_page = excluded.selected_page,
                    updated_at = MAX(reader_state.updated_at, excluded.updated_at)
                """,
                arguments: [
                    targetLibraryID,
                    targetKey,
                    row["locator_json"],
                    row["fraction_complete"],
                    row["selected_page"],
                    row["updated_at"],
                ]
            )
        }
    }

    private static func copyRelationships(
        keyMap: [String: String],
        sourceLibraryID: Int64,
        targetLibraryID: Int64,
        database: Database
    ) throws {
        for row in try Row.fetchAll(
            database,
            sql: "SELECT * FROM app_relationships WHERE library_id = ?",
            arguments: [sourceLibraryID]
        ) {
            let sourceKey: String = row["source_item_key"]
            let targetKey: String = row["target_item_key"]
            guard let mappedSource = keyMap[sourceKey], let mappedTarget = keyMap[targetKey] else {
                continue
            }
            try database.execute(
                sql: """
                INSERT INTO app_relationships (
                    library_id, relationship_id, source_item_key, target_item_key,
                    relationship_kind, confidence, note, raw_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (library_id, relationship_id) DO UPDATE SET
                    source_item_key = excluded.source_item_key,
                    target_item_key = excluded.target_item_key,
                    relationship_kind = excluded.relationship_kind,
                    confidence = excluded.confidence,
                    note = excluded.note,
                    raw_json = excluded.raw_json
                """,
                arguments: [
                    targetLibraryID,
                    row["relationship_id"],
                    mappedSource,
                    mappedTarget,
                    row["relationship_kind"],
                    row["confidence"],
                    row["note"],
                    row["raw_json"],
                ]
            )
        }
    }

    private static func copyAttachmentCache(
        keyMap: [String: String],
        sourceLibraryID: Int64,
        targetLibraryID: Int64,
        database: Database
    ) throws {
        for row in try Row.fetchAll(
            database,
            sql: "SELECT * FROM attachment_projections WHERE library_id = ?",
            arguments: [sourceLibraryID]
        ) {
            let sourceKey: String = row["item_key"]
            guard let targetKey = keyMap[sourceKey] else {
                continue
            }
            try database.execute(
                sql: """
                UPDATE attachment_projections SET cache_state = ?, local_path = ?,
                    verified_sha256 = ?, downloaded_at = ?
                WHERE library_id = ? AND item_key = ?
                """,
                arguments: [
                    row["cache_state"],
                    row["local_path"],
                    row["verified_sha256"],
                    row["downloaded_at"],
                    targetLibraryID,
                    targetKey,
                ]
            )
        }
    }
}
