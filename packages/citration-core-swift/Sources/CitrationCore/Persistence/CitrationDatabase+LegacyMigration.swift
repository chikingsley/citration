import Foundation
import GRDB

extension CitrationDatabase {
    func completedLegacyMigrationReport(
        name: String
    ) throws -> LegacyLibraryMigrationReport? {
        try databaseQueue.read { database in
            guard
                let reportData = try Data.fetchOne(
                    database,
                    sql: """
                    SELECT report_json FROM legacy_migration_runs
                    WHERE migration_name = ? AND status = 'completed'
                    """,
                    arguments: [name]
                )
            else {
                return nil
            }
            return try JSONDecoder().decode(LegacyLibraryMigrationReport.self, from: reportData)
        }
    }

    func beginLegacyMigration(name: String, fingerprint: String, backupURL: URL) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                INSERT INTO legacy_migration_runs (
                    migration_name, source_fingerprint, status, backup_path,
                    report_json, error_message, started_at, completed_at
                ) VALUES (?, ?, 'running', ?, NULL, NULL, ?, NULL)
                ON CONFLICT (migration_name) DO UPDATE SET
                    source_fingerprint = excluded.source_fingerprint,
                    status = excluded.status,
                    backup_path = excluded.backup_path,
                    report_json = NULL,
                    error_message = NULL,
                    started_at = excluded.started_at,
                    completed_at = NULL
                """,
                arguments: [name, fingerprint, backupURL.path, Date().timeIntervalSince1970]
            )
        }
    }

    func completeLegacyMigration(name: String, report: LegacyLibraryMigrationReport) throws {
        let reportData = try JSONEncoder().encode(report)
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                UPDATE legacy_migration_runs
                SET status = 'completed', report_json = ?, error_message = NULL, completed_at = ?
                WHERE migration_name = ?
                """,
                arguments: [reportData, Date().timeIntervalSince1970, name]
            )
        }
    }

    func failLegacyMigration(name: String, error: any Error) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                UPDATE legacy_migration_runs
                SET status = 'failed', error_message = ?, completed_at = ?
                WHERE migration_name = ?
                """,
                arguments: [String(describing: error), Date().timeIntervalSince1970, name]
            )
        }
    }

    func resetLegacyImport(libraryID: Int64) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                DELETE FROM library_search
                WHERE library_id = ? AND object_key IN (
                    SELECT migrated_object_key FROM legacy_records
                    WHERE library_id = ? AND migrated_object_key IS NOT NULL
                );
                DELETE FROM reader_state
                WHERE library_id = ? AND item_key IN (
                    SELECT migrated_object_key FROM legacy_records
                    WHERE library_id = ? AND entity_kind = 'readerProgress'
                );
                DELETE FROM app_relationships
                WHERE library_id = ? AND relationship_id IN (
                    SELECT legacy_id FROM legacy_records
                    WHERE library_id = ? AND entity_kind = 'relationship'
                );
                DELETE FROM item_projections
                WHERE library_id = ? AND item_key IN (
                    SELECT migrated_object_key FROM legacy_records
                    WHERE library_id = ? AND migrated_object_kind = 'item'
                );
                DELETE FROM collection_projections
                WHERE library_id = ? AND collection_key IN (
                    SELECT migrated_object_key FROM legacy_records
                    WHERE library_id = ? AND migrated_object_kind = 'collection'
                );
                DELETE FROM zotero_objects
                WHERE library_id = ? AND object_key IN (
                    SELECT migrated_object_key FROM legacy_records
                    WHERE library_id = ? AND migrated_object_key IS NOT NULL
                );
                DELETE FROM app_object_identity
                WHERE library_id = ? AND object_key IN (
                    SELECT migrated_object_key FROM legacy_records
                    WHERE library_id = ? AND migrated_object_key IS NOT NULL
                );
                DELETE FROM legacy_records WHERE library_id = ?;
                """,
                arguments: [
                    libraryID, libraryID,
                    libraryID, libraryID,
                    libraryID, libraryID,
                    libraryID, libraryID,
                    libraryID, libraryID,
                    libraryID, libraryID,
                    libraryID, libraryID,
                    libraryID,
                ]
            )
        }
    }

    func storeLegacySupportState(
        records: [LegacyMigrationObject],
        relationships: [LegacyRelationshipProjection],
        readerProgress: [LegacyReaderProgressProjection],
        attachmentPaths: [(itemKey: String, fileURL: URL)],
        libraryID: Int64
    ) throws {
        try databaseQueue.write { database in
            for record in records {
                try database.execute(
                    sql: """
                    INSERT INTO legacy_records (
                        library_id, entity_kind, legacy_id, payload_json,
                        migrated_object_kind, migrated_object_key
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT (library_id, entity_kind, legacy_id) DO UPDATE SET
                        payload_json = excluded.payload_json,
                        migrated_object_kind = excluded.migrated_object_kind,
                        migrated_object_key = excluded.migrated_object_key
                    """,
                    arguments: [
                        libraryID,
                        record.entityKind,
                        record.legacyID,
                        record.rawPayload,
                        record.objectKind?.rawValue,
                        record.objectKey,
                    ]
                )
                if
                    let objectKind = record.objectKind,
                    let objectKey = record.objectKey,
                    let appUUID = UUID(uuidString: record.legacyID)
                {
                    let dates = Self.legacyIdentityDates(for: record)
                    try Self.upsertAppIdentity(
                        uuid: appUUID,
                        kind: objectKind,
                        key: objectKey,
                        dates: dates,
                        libraryID: libraryID,
                        database: database
                    )
                }
            }

            try Self.storeLegacyMemberships(records, libraryID: libraryID, database: database)
            try Self.storeLegacyRelationships(relationships, libraryID: libraryID, database: database)
            try Self.storeLegacyReaderProgress(readerProgress, libraryID: libraryID, database: database)
            try Self.storeLegacyAttachmentPaths(attachmentPaths, libraryID: libraryID, database: database)
        }
    }

    public func inspectLegacyMigration(name: String, libraryID: Int64) throws -> LegacyMigrationInspection {
        try databaseQueue.read { database in
            try LegacyMigrationInspection(
                status: String.fetchOne(
                    database,
                    sql: "SELECT status FROM legacy_migration_runs WHERE migration_name = ?",
                    arguments: [name]
                ),
                legacyRecordCount: Self.count(
                    database,
                    table: "legacy_records",
                    libraryID: libraryID
                ),
                relationshipCount: Self.count(
                    database,
                    table: "app_relationships",
                    libraryID: libraryID
                ),
                readerStateCount: Self.count(database, table: "reader_state", libraryID: libraryID),
                downloadedAttachmentCount: Int.fetchOne(
                    database,
                    sql: """
                    SELECT COUNT(*) FROM attachment_projections
                    WHERE library_id = ? AND cache_state = 'downloaded' AND local_path IS NOT NULL
                    """,
                    arguments: [libraryID]
                ) ?? 0
            )
        }
    }

    func legacyRecordPayload(
        libraryID: Int64,
        entityKind: String,
        legacyID: String
    ) throws -> Data? {
        try databaseQueue.read { database in
            try Data.fetchOne(
                database,
                sql: """
                SELECT payload_json FROM legacy_records
                WHERE library_id = ? AND entity_kind = ? AND legacy_id = ?
                """,
                arguments: [libraryID, entityKind, legacyID]
            )
        }
    }

    func legacyMigratedObjectKey(
        libraryID: Int64,
        entityKind: String,
        legacyID: String
    ) throws -> String? {
        try databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: """
                SELECT migrated_object_key FROM legacy_records
                WHERE library_id = ? AND entity_kind = ? AND legacy_id = ?
                """,
                arguments: [libraryID, entityKind, legacyID]
            )
        }
    }

    func localAttachmentPath(libraryID: Int64, itemKey: String) throws -> String? {
        try databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: """
                SELECT local_path FROM attachment_projections
                WHERE library_id = ? AND item_key = ?
                """,
                arguments: [libraryID, itemKey]
            )
        }
    }

    private static func count(_ database: Database, table: String, libraryID: Int64) throws -> Int {
        try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM \(table) WHERE library_id = ?",
            arguments: [libraryID]
        ) ?? 0
    }

    private static func upsertAppIdentity(
        uuid: UUID,
        kind: ZoteroObjectKind,
        key: String,
        dates: (createdAt: Date, updatedAt: Date),
        libraryID: Int64,
        database: Database
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO app_object_identity (
                library_id, object_kind, object_key, app_uuid, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (library_id, object_kind, object_key) DO UPDATE SET
                app_uuid = excluded.app_uuid,
                updated_at = excluded.updated_at
            """,
            arguments: [
                libraryID,
                kind.rawValue,
                key,
                uuid.uuidString,
                dates.createdAt.timeIntervalSince1970,
                dates.updatedAt.timeIntervalSince1970,
            ]
        )
    }

    private static func legacyIdentityDates(
        for record: LegacyMigrationObject
    ) -> (createdAt: Date, updatedAt: Date) {
        let decoder = JSONDecoder()
        if let item = try? decoder.decode(BCItem.self, from: record.rawPayload) {
            return (item.createdAt, item.updatedAt)
        }
        if let collection = try? decoder.decode(LibraryCollection.self, from: record.rawPayload) {
            return (collection.createdAt, collection.updatedAt)
        }
        if let note = try? decoder.decode(LibraryNote.self, from: record.rawPayload) {
            return (note.createdAt, note.updatedAt)
        }
        if let annotation = try? decoder.decode(LibraryAnnotation.self, from: record.rawPayload) {
            return (annotation.createdAt, annotation.updatedAt)
        }
        return (.distantPast, .distantPast)
    }

    private static func storeLegacyMemberships(
        _ records: [LegacyMigrationObject],
        libraryID: Int64,
        database: Database
    ) throws {
        let decoder = JSONDecoder()
        for record in records where record.entityKind == "membership" {
            let membership = try decoder.decode(LibraryCollectionMembership.self, from: record.rawPayload)
            guard
                let collectionKey = try objectKey(for: membership.collectionID, libraryID: libraryID, database: database),
                let itemKey = try objectKey(for: membership.itemID, libraryID: libraryID, database: database)
            else {
                continue
            }
            try database.execute(
                sql: """
                INSERT INTO app_collection_memberships (
                    library_id, collection_key, item_key, membership_uuid, created_at
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (library_id, collection_key, item_key) DO UPDATE SET
                    membership_uuid = excluded.membership_uuid,
                    created_at = excluded.created_at
                """,
                arguments: [
                    libraryID,
                    collectionKey,
                    itemKey,
                    membership.id.uuidString,
                    membership.createdAt.timeIntervalSince1970,
                ]
            )
        }
    }

    private static func objectKey(
        for uuid: UUID,
        libraryID: Int64,
        database: Database
    ) throws -> String? {
        try String.fetchOne(
            database,
            sql: "SELECT object_key FROM app_object_identity WHERE library_id = ? AND app_uuid = ?",
            arguments: [libraryID, uuid.uuidString]
        )
    }

    private static func storeLegacyRelationships(
        _ relationships: [LegacyRelationshipProjection],
        libraryID: Int64,
        database: Database
    ) throws {
        for value in relationships {
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
                    libraryID,
                    value.relationship.id.uuidString,
                    value.sourceKey,
                    value.targetKey,
                    value.relationship.kind.rawValue,
                    value.relationship.confidence,
                    value.relationship.note,
                    value.rawPayload,
                ]
            )
        }
    }

    private static func storeLegacyReaderProgress(
        _ progress: [LegacyReaderProgressProjection],
        libraryID: Int64,
        database: Database
    ) throws {
        for value in progress {
            try database.execute(
                sql: """
                INSERT INTO reader_state (
                    library_id, item_key, locator_json, fraction_complete, selected_page, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT (library_id, item_key) DO UPDATE SET
                    locator_json = excluded.locator_json,
                    fraction_complete = excluded.fraction_complete,
                    selected_page = excluded.selected_page,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    libraryID,
                    value.itemKey,
                    value.rawPayload,
                    value.progress.fractionComplete ?? 0,
                    value.progress.location.pageNumber,
                    value.progress.updatedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    private static func storeLegacyAttachmentPaths(
        _ paths: [(itemKey: String, fileURL: URL)],
        libraryID: Int64,
        database: Database
    ) throws {
        for value in paths {
            try database.execute(
                sql: """
                UPDATE attachment_projections
                SET cache_state = 'downloaded', local_path = ?, downloaded_at = ?
                WHERE library_id = ? AND item_key = ?
                """,
                arguments: [
                    value.fileURL.path,
                    Date().timeIntervalSince1970,
                    libraryID,
                    value.itemKey,
                ]
            )
        }
    }
}

private extension ReaderLocation {
    var pageNumber: Int? {
        guard case let .page(number) = self else {
            return nil
        }
        return number
    }
}
