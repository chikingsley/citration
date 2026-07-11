import Foundation
import GRDB

public extension CitrationDatabase {
    func markLocalDeletion(kind: ZoteroObjectKind, key: String, libraryID: Int64) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                UPDATE zotero_objects
                SET sync_state = 'deleted', is_deleted = 1, failure_message = NULL, updated_at = ?
                WHERE library_id = ? AND object_kind = ? AND object_key = ?
                """,
                arguments: [Date().timeIntervalSince1970, libraryID, kind.rawValue, key]
            )
            try Self.deleteProjection(key: key, kind: kind, libraryID: libraryID, database: database)
        }
    }

    func pendingUploads(
        kind: ZoteroObjectKind,
        libraryID: Int64,
        limit: Int = 50,
        now: Date = .now
    ) throws -> [ZoteroStoredObject] {
        try databaseQueue.read { database in
            let keys = try String.fetchAll(
                database,
                sql: """
                SELECT object_key FROM zotero_objects object
                WHERE library_id = ? AND object_kind = ? AND is_deleted = 0
                  AND (
                    sync_state = 'dirty'
                    OR (
                      sync_state = 'failed'
                      AND NOT EXISTS (
                        SELECT 1 FROM synchronization_failures failure
                        WHERE failure.library_id = object.library_id
                          AND failure.object_kind = object.object_kind
                          AND failure.object_key = object.object_key
                          AND failure.operation = 'merge-conflict'
                          AND failure.resolved_at IS NULL
                      )
                      AND NOT EXISTS (
                        SELECT 1 FROM synchronization_failures failure
                        WHERE failure.library_id = object.library_id
                          AND failure.object_kind = object.object_kind
                          AND failure.object_key = object.object_key
                          AND failure.resolved_at IS NULL
                          AND failure.next_retry_at > ?
                      )
                    )
                  )
                ORDER BY updated_at, object_key
                LIMIT ?
                """,
                arguments: [libraryID, kind.rawValue, now.timeIntervalSince1970, limit]
            )
            return try keys.compactMap {
                try Self.fetchStoredObject(
                    libraryID: libraryID,
                    kind: kind,
                    key: $0,
                    database: database
                )
            }
        }
    }

    func pendingDeletions(
        kind: ZoteroObjectKind,
        libraryID: Int64,
        limit: Int = 50,
        now: Date = .now
    ) throws -> [String] {
        try databaseQueue.read { database in
            try String.fetchAll(
                database,
                sql: """
                SELECT object_key FROM zotero_objects object
                WHERE library_id = ? AND object_kind = ?
                    AND sync_state = 'deleted' AND is_deleted = 1
                    AND NOT EXISTS (
                      SELECT 1 FROM synchronization_failures failure
                      WHERE failure.library_id = object.library_id
                        AND failure.object_kind = object.object_kind
                        AND failure.object_key = object.object_key
                        AND failure.resolved_at IS NULL
                        AND failure.next_retry_at > ?
                    )
                ORDER BY updated_at, object_key LIMIT ?
                """,
                arguments: [libraryID, kind.rawValue, now.timeIntervalSince1970, limit]
            )
        }
    }

    func applyWriteReport(
        _ report: ZoteroWriteReport,
        batch: [ZoteroStoredObject],
        kind: ZoteroObjectKind,
        libraryVersion: Int64,
        libraryID: Int64
    ) throws {
        try databaseQueue.write { database in
            for (indexText, object) in report.successful {
                guard let index = Int(indexText), batch.indices.contains(index) else {
                    continue
                }
                try Self.storeSuccessfulWrite(
                    object,
                    kind: kind,
                    libraryID: libraryID,
                    database: database
                )
            }
            for indexText in report.unchanged.keys {
                guard let index = Int(indexText), batch.indices.contains(index) else {
                    continue
                }
                try Self.markWriteSynced(batch[index], libraryID: libraryID, database: database)
            }
            for (indexText, failure) in report.failed {
                guard let index = Int(indexText), batch.indices.contains(index) else {
                    continue
                }
                try Self.markWriteFailed(
                    batch[index],
                    failure: failure,
                    libraryID: libraryID,
                    database: database
                )
            }
            try database.execute(
                sql: "UPDATE libraries SET current_version = ?, updated_at = ? WHERE id = ?",
                arguments: [libraryVersion, Date().timeIntervalSince1970, libraryID]
            )
        }
    }

    func markDeletionsUploaded(
        keys: [String],
        kind: ZoteroObjectKind,
        libraryVersion: Int64,
        libraryID: Int64
    ) throws {
        try databaseQueue.write { database in
            for key in keys {
                try database.execute(
                    sql: """
                    UPDATE zotero_objects SET object_version = ?, sync_state = 'synced',
                        is_deleted = 1, failure_message = NULL, updated_at = ?
                    WHERE library_id = ? AND object_kind = ? AND object_key = ?
                    """,
                    arguments: [libraryVersion, Date().timeIntervalSince1970, libraryID, kind.rawValue, key]
                )
                try Self.resolveSyncFailure(
                    key: key,
                    kind: kind,
                    operation: "delete",
                    libraryID: libraryID,
                    database: database
                )
            }
            try database.execute(
                sql: "UPDATE libraries SET current_version = ?, updated_at = ? WHERE id = ?",
                arguments: [libraryVersion, Date().timeIntervalSince1970, libraryID]
            )
        }
    }

    func recordWriteTransportFailure(
        objects: [ZoteroStoredObject],
        operation: String,
        message: String,
        libraryID: Int64
    ) throws {
        try databaseQueue.write { database in
            for object in objects {
                try Self.recordSyncFailure(
                    key: object.key,
                    kind: object.kind,
                    operation: operation,
                    message: message,
                    nextRetryAt: Date().addingTimeInterval(30),
                    libraryID: libraryID,
                    database: database
                )
                try database.execute(
                    sql: """
                    UPDATE zotero_objects SET sync_state = 'failed', failure_message = ?, updated_at = ?
                    WHERE library_id = ? AND object_kind = ? AND object_key = ?
                    """,
                    arguments: [
                        message,
                        Date().timeIntervalSince1970,
                        libraryID,
                        object.kind.rawValue,
                        object.key,
                    ]
                )
            }
        }
    }

    func recordDeletionTransportFailure(
        keys: [String],
        kind: ZoteroObjectKind,
        message: String,
        libraryID: Int64
    ) throws {
        try databaseQueue.write { database in
            for key in keys {
                try Self.recordSyncFailure(
                    key: key,
                    kind: kind,
                    operation: "delete",
                    message: message,
                    nextRetryAt: Date().addingTimeInterval(30),
                    libraryID: libraryID,
                    database: database
                )
                try database.execute(
                    sql: """
                    UPDATE zotero_objects SET failure_message = ?, updated_at = ?
                    WHERE library_id = ? AND object_kind = ? AND object_key = ?
                    """,
                    arguments: [message, Date().timeIntervalSince1970, libraryID, kind.rawValue, key]
                )
            }
        }
    }

    func unresolvedSyncFailureCount(libraryID: Int64) throws -> Int {
        try databaseQueue.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM synchronization_failures WHERE library_id = ? AND resolved_at IS NULL",
                arguments: [libraryID]
            ) ?? 0
        }
    }

    private static func storeSuccessfulWrite(
        _ object: ZoteroRawObject,
        kind: ZoteroObjectKind,
        libraryID: Int64,
        database: Database
    ) throws {
        let stored = try ZoteroStoredObject(kind: kind, object: object)
        try upsert(object: stored, libraryID: libraryID, database: database)
        try resolveSyncFailure(
            key: stored.key,
            kind: kind,
            operation: "upload",
            libraryID: libraryID,
            database: database
        )
        if kind == .item {
            try replaceItemProjection(object: object, libraryID: libraryID, database: database)
        } else if kind == .collection {
            try upsertCollectionProjection(object: object, libraryID: libraryID, database: database)
        }
    }

    private static func markWriteSynced(
        _ object: ZoteroStoredObject,
        libraryID: Int64,
        database: Database
    ) throws {
        let synced = ZoteroStoredObject(
            kind: object.kind,
            key: object.key,
            version: object.version,
            objectType: object.objectType,
            current: object.current,
            pristine: object.current,
            syncState: .synced
        )
        try upsert(object: synced, libraryID: libraryID, database: database)
        try resolveSyncFailure(
            key: object.key,
            kind: object.kind,
            operation: "upload",
            libraryID: libraryID,
            database: database
        )
    }

    private static func markWriteFailed(
        _ object: ZoteroStoredObject,
        failure: ZoteroWriteFailure,
        libraryID: Int64,
        database: Database
    ) throws {
        try recordSyncFailure(
            key: object.key,
            kind: object.kind,
            operation: "upload",
            message: "Write failed with status \(failure.code): \(failure.message)",
            nextRetryAt: Date().addingTimeInterval(30),
            libraryID: libraryID,
            database: database
        )
        try database.execute(
            sql: """
            UPDATE zotero_objects SET sync_state = 'failed', failure_message = ?, updated_at = ?
            WHERE library_id = ? AND object_kind = ? AND object_key = ?
            """,
            arguments: [failure.message, Date().timeIntervalSince1970, libraryID, object.kind.rawValue, object.key]
        )
    }
}
