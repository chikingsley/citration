import Dispatch
import Foundation
import GRDB

// MARK: - ZoteroSyncFailureSummary

public struct ZoteroSyncFailureSummary: Hashable, Identifiable, Sendable {
    public let id: Int64
    public let objectKind: ZoteroObjectKind
    public let objectKey: String
    public let operation: String
    public let message: String
    public let retryCount: Int
    public let nextRetryAt: Date?
}

// MARK: - ZoteroSyncStatusSnapshot

public struct ZoteroSyncStatusSnapshot: Hashable, Sendable {
    public let currentVersion: Int64
    public let pendingUploadCount: Int
    public let pendingDeletionCount: Int
    public let downloadingAttachmentCount: Int
    public let staleAttachmentCount: Int
    public let failedAttachmentCount: Int
    public let failures: [ZoteroSyncFailureSummary]

    public var pendingChangeCount: Int {
        pendingUploadCount + pendingDeletionCount
    }
}

public extension CitrationDatabase {
    func syncStatusSnapshot(libraryID: Int64) throws -> ZoteroSyncStatusSnapshot {
        try databaseQueue.read { database in
            try Self.fetchSyncStatusSnapshot(libraryID: libraryID, database: database)
        }
    }

    func observeSyncStatus(
        libraryID: Int64,
        onError: @escaping @Sendable (any Error) -> Void,
        onChange: @escaping @Sendable (ZoteroSyncStatusSnapshot) -> Void
    ) -> CitrationDatabaseObservation {
        let observation = ValueObservation.tracking { database in
            try Self.fetchSyncStatusSnapshot(libraryID: libraryID, database: database)
        }
        let cancellable = observation.start(
            in: databaseQueue,
            scheduling: .async(onQueue: DispatchQueue(label: "CitrationCore.SyncStatusObservation")),
            onError: onError,
            onChange: onChange
        )
        return CitrationDatabaseObservation(cancellable)
    }

    private static func fetchSyncStatusSnapshot(
        libraryID: Int64,
        database: Database
    ) throws -> ZoteroSyncStatusSnapshot {
        let currentVersion = try Int64.fetchOne(
            database,
            sql: "SELECT current_version FROM libraries WHERE id = ?",
            arguments: [libraryID]
        ) ?? 0
        let pendingUploadCount = try Int.fetchOne(
            database,
            sql: """
            SELECT COUNT(*) FROM zotero_objects
            WHERE library_id = ? AND is_deleted = 0 AND sync_state IN ('dirty', 'failed')
            """,
            arguments: [libraryID]
        ) ?? 0
        let pendingDeletionCount = try Int.fetchOne(
            database,
            sql: """
            SELECT COUNT(*) FROM zotero_objects
            WHERE library_id = ? AND is_deleted = 1 AND sync_state = 'deleted'
            """,
            arguments: [libraryID]
        ) ?? 0
        let attachmentCounts = try Row.fetchOne(
            database,
            sql: """
            SELECT
              SUM(CASE WHEN cache_state = 'downloading' THEN 1 ELSE 0 END) AS downloading,
              SUM(CASE WHEN cache_state = 'stale' THEN 1 ELSE 0 END) AS stale,
              SUM(CASE WHEN cache_state = 'failed' THEN 1 ELSE 0 END) AS failed
            FROM attachment_projections WHERE library_id = ?
            """,
            arguments: [libraryID]
        )
        let failures = try fetchFailures(libraryID: libraryID, database: database)
        return ZoteroSyncStatusSnapshot(
            currentVersion: currentVersion,
            pendingUploadCount: pendingUploadCount,
            pendingDeletionCount: pendingDeletionCount,
            downloadingAttachmentCount: attachmentCounts?["downloading"] ?? 0,
            staleAttachmentCount: attachmentCounts?["stale"] ?? 0,
            failedAttachmentCount: attachmentCounts?["failed"] ?? 0,
            failures: failures
        )
    }

    private static func fetchFailures(
        libraryID: Int64,
        database: Database
    ) throws -> [ZoteroSyncFailureSummary] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT id, object_kind, object_key, operation, message, retry_count, next_retry_at
            FROM synchronization_failures
            WHERE library_id = ? AND resolved_at IS NULL
            ORDER BY COALESCE(last_attempt_at, created_at) DESC, id DESC
            """,
            arguments: [libraryID]
        ).map { row in
            let kindText: String = row["object_kind"]
            let nextRetryTimestamp: Double? = row["next_retry_at"]
            return ZoteroSyncFailureSummary(
                id: row["id"],
                objectKind: ZoteroObjectKind(rawValue: kindText),
                objectKey: row["object_key"],
                operation: row["operation"],
                message: row["message"],
                retryCount: row["retry_count"],
                nextRetryAt: nextRetryTimestamp.map(Date.init(timeIntervalSince1970:))
            )
        }
    }
}
