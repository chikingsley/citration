import Foundation
import GRDB

public extension CitrationDatabase {
    func integrateRemoteCollections(_ objects: [ZoteroRawObject], libraryID: Int64) throws {
        try integrateRemoteVersionedObjects(objects, kind: .collection, libraryID: libraryID)
    }

    func integrateRemoteItems(_ objects: [ZoteroRawObject], libraryID: Int64) throws {
        try integrateRemoteVersionedObjects(objects, kind: .item, libraryID: libraryID)
    }

    private func integrateRemoteVersionedObjects(
        _ objects: [ZoteroRawObject],
        kind: ZoteroObjectKind,
        libraryID: Int64
    ) throws {
        try databaseQueue.write { database in
            for object in objects {
                let remote = try ZoteroStoredObject(kind: kind, object: object)
                let existing = try Self.fetchStoredObject(
                    libraryID: libraryID,
                    kind: kind,
                    key: remote.key,
                    database: database
                )
                let integrated = try Self.integrate(
                    remote: remote,
                    existing: existing,
                    libraryID: libraryID,
                    database: database
                )
                guard integrated.syncState != .failed else {
                    continue
                }
                let projected = try ZoteroRawObject(rawValue: integrated.current)
                if kind == .item {
                    try Self.replaceItemProjection(object: projected, libraryID: libraryID, database: database)
                } else if kind == .collection {
                    try Self.upsertCollectionProjection(object: projected, libraryID: libraryID, database: database)
                }
            }
        }
    }

    private static func integrate(
        remote: ZoteroStoredObject,
        existing: ZoteroStoredObject?,
        libraryID: Int64,
        database: Database
    ) throws -> ZoteroStoredObject {
        guard let existing, existing.syncState != .synced else {
            try upsert(object: remote, libraryID: libraryID, database: database)
            return remote
        }
        return try mergeRemote(remote, into: existing, libraryID: libraryID, database: database)
    }

    static func fetchStoredObject(
        libraryID: Int64,
        kind: ZoteroObjectKind,
        key: String,
        database: Database
    ) throws -> ZoteroStoredObject? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                SELECT object_version, object_type, current_json, pristine_json,
                       sync_state, is_deleted, failure_message
                FROM zotero_objects
                WHERE library_id = ? AND object_kind = ? AND object_key = ?
                """,
                arguments: [libraryID, kind.rawValue, key]
            )
        else {
            return nil
        }
        let stateValue: String = row["sync_state"]
        guard let state = ZoteroSyncState(rawValue: stateValue) else {
            throw CitrationDatabaseError.unknownSyncState(stateValue)
        }
        let currentData: Data = row["current_json"]
        let pristineData: Data = row["pristine_json"]
        return try ZoteroStoredObject(
            kind: kind,
            key: key,
            version: row["object_version"],
            objectType: row["object_type"],
            current: ZoteroJSON.decode(currentData),
            pristine: ZoteroJSON.decode(pristineData),
            syncState: state,
            isDeleted: row["is_deleted"],
            failureMessage: row["failure_message"]
        )
    }

    private static func mergeRemote(
        _ remote: ZoteroStoredObject,
        into local: ZoteroStoredObject,
        libraryID: Int64,
        database: Database
    ) throws -> ZoteroStoredObject {
        guard local.syncState != .deleted else {
            return try localDeletionConflict(remote: remote, local: local, libraryID: libraryID, database: database)
        }
        switch ZoteroThreeWayMerge.merge(base: local.pristine, local: local.current, remote: remote.current) {
        case let .merged(current):
            let merged = ZoteroStoredObject(
                kind: remote.kind,
                key: remote.key,
                version: remote.version,
                objectType: remote.objectType,
                current: current,
                pristine: remote.current,
                syncState: .dirty
            )
            try upsert(object: merged, libraryID: libraryID, database: database)
            try resolveSyncFailure(
                key: remote.key,
                kind: remote.kind,
                operation: "merge-conflict",
                libraryID: libraryID,
                database: database
            )
            return merged

        case let .conflict(fields):
            return try concurrentConflict(
                fields: fields,
                remote: remote,
                local: local,
                libraryID: libraryID,
                database: database
            )
        }
    }

    private static func localDeletionConflict(
        remote: ZoteroStoredObject,
        local: ZoteroStoredObject,
        libraryID: Int64,
        database: Database
    ) throws -> ZoteroStoredObject {
        let message = "Remote update conflicts with local deletion"
        try recordSyncFailure(
            key: local.key,
            kind: local.kind,
            operation: "merge-conflict",
            message: message,
            details: conflictDetails(
                fields: ["<local-deletion>"],
                base: local.pristine,
                local: local.current,
                remote: remote.current
            ),
            libraryID: libraryID,
            database: database
        )
        return try storeFailed(local: local, message: message, libraryID: libraryID, database: database)
    }

    private static func concurrentConflict(
        fields: [String],
        remote: ZoteroStoredObject,
        local: ZoteroStoredObject,
        libraryID: Int64,
        database: Database
    ) throws -> ZoteroStoredObject {
        let message = "Concurrent changes conflict in fields: \(fields.joined(separator: ", "))"
        try recordSyncFailure(
            key: local.key,
            kind: local.kind,
            operation: "merge-conflict",
            message: message,
            details: conflictDetails(fields: fields, base: local.pristine, local: local.current, remote: remote.current),
            libraryID: libraryID,
            database: database
        )
        return try storeFailed(local: local, message: message, libraryID: libraryID, database: database)
    }

    private static func storeFailed(
        local: ZoteroStoredObject,
        message: String,
        libraryID: Int64,
        database: Database
    ) throws -> ZoteroStoredObject {
        let failed = ZoteroStoredObject(
            kind: local.kind,
            key: local.key,
            version: local.version,
            objectType: local.objectType,
            current: local.current,
            pristine: local.pristine,
            syncState: .failed,
            isDeleted: local.isDeleted,
            failureMessage: message
        )
        try upsert(object: failed, libraryID: libraryID, database: database)
        return failed
    }

    static func conflictDetails(
        fields: [String],
        base: JSONValue,
        local: JSONValue,
        remote: JSONValue
    ) -> JSONValue {
        .object([
            "fields": .array(fields.map(JSONValue.string)),
            "base": base,
            "local": local,
            "remote": remote,
        ])
    }

    static func recordSyncFailure(
        key: String,
        kind: ZoteroObjectKind,
        operation: String,
        message: String,
        details: JSONValue? = nil,
        nextRetryAt: Date? = nil,
        libraryID: Int64,
        database: Database
    ) throws {
        let existingID = try Int64.fetchOne(
            database,
            sql: """
            SELECT id FROM synchronization_failures
            WHERE library_id = ? AND object_kind = ? AND object_key = ?
                AND operation = ? AND resolved_at IS NULL
            ORDER BY id DESC LIMIT 1
            """,
            arguments: [libraryID, kind.rawValue, key, operation]
        )
        let detailsData = try details.map { try ZoteroJSON.encode($0) }
        if let existingID {
            try updateSyncFailure(
                id: existingID,
                message: message,
                detailsData: detailsData,
                nextRetryAt: nextRetryAt,
                database: database
            )
        } else {
            try insertSyncFailure(
                values: SyncFailureValues(
                    key: key,
                    kind: kind,
                    operation: operation,
                    message: message,
                    detailsData: detailsData,
                    nextRetryAt: nextRetryAt
                ),
                libraryID: libraryID,
                database: database
            )
        }
    }

    private static func updateSyncFailure(
        id: Int64,
        message: String,
        detailsData: Data?,
        nextRetryAt: Date?,
        database: Database
    ) throws {
        try database.execute(
            sql: """
            UPDATE synchronization_failures
            SET message = ?, details_json = ?, retry_count = retry_count + 1,
                next_retry_at = ?, last_attempt_at = ?
            WHERE id = ?
            """,
            arguments: [message, detailsData, nextRetryAt?.timeIntervalSince1970, Date().timeIntervalSince1970, id]
        )
    }

    private static func insertSyncFailure(
        values: SyncFailureValues,
        libraryID: Int64,
        database: Database
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO synchronization_failures (
                library_id, object_kind, object_key, operation, message,
                next_retry_at, details_json, created_at, last_attempt_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                libraryID,
                values.kind.rawValue,
                values.key,
                values.operation,
                values.message,
                values.nextRetryAt?.timeIntervalSince1970,
                values.detailsData,
                Date().timeIntervalSince1970,
                Date().timeIntervalSince1970,
            ]
        )
    }

    static func resolveSyncFailure(
        key: String,
        kind: ZoteroObjectKind,
        operation: String,
        libraryID: Int64,
        database: Database
    ) throws {
        try database.execute(
            sql: """
            UPDATE synchronization_failures SET resolved_at = ?
            WHERE library_id = ? AND object_kind = ? AND object_key = ?
                AND operation = ? AND resolved_at IS NULL
            """,
            arguments: [Date().timeIntervalSince1970, libraryID, kind.rawValue, key, operation]
        )
    }
}

// MARK: - SyncFailureValues

private struct SyncFailureValues {
    let key: String
    let kind: ZoteroObjectKind
    let operation: String
    let message: String
    let detailsData: Data?
    let nextRetryAt: Date?
}
