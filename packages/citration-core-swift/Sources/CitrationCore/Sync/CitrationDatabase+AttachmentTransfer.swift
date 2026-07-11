import Foundation
import GRDB

// MARK: - ZoteroAttachmentCacheState

public enum ZoteroAttachmentCacheState: String, Sendable {
    case notDownloaded
    case downloading
    case downloaded
    case failed
    case stale
}

// MARK: - ZoteroAttachmentCacheRecord

public struct ZoteroAttachmentCacheRecord: Sendable {
    public let itemKey: String
    public let parentItemKey: String?
    public let linkMode: String
    public let contentType: String
    public let filename: String
    public let remoteMD5: String?
    public let remoteMTime: Int64?
    public let cacheState: ZoteroAttachmentCacheState
    public let localURL: URL?
    public let verifiedMD5: String?
    public let verifiedSHA256: String?
    public let transferError: String?
}

public extension CitrationDatabase {
    func attachmentCacheRecord(libraryID: Int64, itemKey: String) throws -> ZoteroAttachmentCacheRecord? {
        try databaseQueue.read { database in
            try Self.attachmentCacheRecord(libraryID: libraryID, itemKey: itemKey, database: database)
        }
    }

    func pendingAttachmentUploads(libraryID: Int64, now: Date = .now) throws -> [ZoteroAttachmentCacheRecord] {
        try databaseQueue.read { database in
            let keys = try String.fetchAll(
                database,
                sql: """
                SELECT attachment.item_key
                FROM attachment_projections attachment
                JOIN zotero_objects object
                  ON object.library_id = attachment.library_id
                 AND object.object_kind = 'item'
                 AND object.object_key = attachment.item_key
                WHERE attachment.library_id = ?
                  AND attachment.link_mode IN ('imported_file', 'imported_url')
                  AND attachment.local_path IS NOT NULL
                  AND object.object_version > 0
                  AND object.sync_state = 'synced'
                  AND object.is_deleted = 0
                  AND NOT EXISTS (
                    SELECT 1 FROM synchronization_failures failure
                    WHERE failure.library_id = attachment.library_id
                      AND failure.object_kind = 'item'
                      AND failure.object_key = attachment.item_key
                      AND failure.operation = 'attachment-upload'
                      AND failure.resolved_at IS NULL
                      AND failure.next_retry_at > ?
                  )
                ORDER BY object.updated_at, attachment.item_key
                """,
                arguments: [libraryID, now.timeIntervalSince1970]
            )
            return try keys.compactMap {
                try Self.attachmentCacheRecord(libraryID: libraryID, itemKey: $0, database: database)
            }
        }
    }

    func markAttachmentTransferStarted(
        libraryID: Int64,
        itemKey: String,
        operation: String
    ) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                UPDATE attachment_projections
                SET cache_state = CASE
                        WHEN ? = 'attachment-download' AND local_path IS NULL THEN 'downloading'
                        ELSE cache_state
                    END,
                    transfer_error = NULL,
                    transfer_attempted_at = ?
                WHERE library_id = ? AND item_key = ?
                """,
                arguments: [operation, Date().timeIntervalSince1970, libraryID, itemKey]
            )
        }
    }

    func markAttachmentTransferComplete(
        libraryID: Int64,
        itemKey: String,
        localURL: URL,
        md5: String,
        sha256: String,
        remoteMTime: Int64?
    ) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                UPDATE attachment_projections
                SET cache_state = 'downloaded', local_path = ?, remote_md5 = ?,
                    remote_mtime = COALESCE(?, remote_mtime), verified_md5 = ?,
                    verified_sha256 = ?, downloaded_at = ?, transfer_error = NULL
                WHERE library_id = ? AND item_key = ?
                """,
                arguments: [
                    localURL.path,
                    md5,
                    remoteMTime,
                    md5,
                    sha256,
                    Date().timeIntervalSince1970,
                    libraryID,
                    itemKey,
                ]
            )
            for operation in ["attachment-download", "attachment-upload"] {
                try Self.resolveSyncFailure(
                    key: itemKey,
                    kind: .item,
                    operation: operation,
                    libraryID: libraryID,
                    database: database
                )
            }
        }
    }

    func markAttachmentTransferFailed(
        libraryID: Int64,
        itemKey: String,
        operation: String,
        message: String
    ) throws {
        try databaseQueue.write { database in
            let safeMessage = Self.redactedTransferMessage(message)
            try database.execute(
                sql: """
                UPDATE attachment_projections
                SET cache_state = CASE WHEN local_path IS NULL THEN 'failed' ELSE cache_state END,
                    transfer_error = ?, transfer_attempted_at = ?
                WHERE library_id = ? AND item_key = ?
                """,
                arguments: [safeMessage, Date().timeIntervalSince1970, libraryID, itemKey]
            )
            try Self.recordSyncFailure(
                key: itemKey,
                kind: .item,
                operation: operation,
                message: safeMessage,
                nextRetryAt: Date().addingTimeInterval(30),
                libraryID: libraryID,
                database: database
            )
        }
    }

    private static func redactedTransferMessage(_ message: String) -> String {
        let withoutURLs = message.replacingOccurrences(
            of: #"(?i)https?://\S+"#,
            with: "<redacted-url>",
            options: .regularExpression
        )
        return String(withoutURLs.prefix(1000))
    }

    private static func attachmentCacheRecord(
        libraryID: Int64,
        itemKey: String,
        database: Database
    ) throws -> ZoteroAttachmentCacheRecord? {
        try Row.fetchOne(
            database,
            sql: """
            SELECT item_key, parent_item_key, link_mode, content_type, filename,
                   remote_md5, remote_mtime, cache_state, local_path, verified_md5,
                   verified_sha256, transfer_error
            FROM attachment_projections WHERE library_id = ? AND item_key = ?
            """,
            arguments: [libraryID, itemKey]
        ).map { row in
            let stateText: String = row["cache_state"]
            guard let state = ZoteroAttachmentCacheState(rawValue: stateText) else {
                throw CitrationDatabaseError.unknownAttachmentCacheState(stateText)
            }
            let path: String? = row["local_path"]
            return ZoteroAttachmentCacheRecord(
                itemKey: row["item_key"],
                parentItemKey: row["parent_item_key"],
                linkMode: row["link_mode"],
                contentType: row["content_type"],
                filename: row["filename"],
                remoteMD5: row["remote_md5"],
                remoteMTime: row["remote_mtime"],
                cacheState: state,
                localURL: path.map { URL(filePath: $0) },
                verifiedMD5: row["verified_md5"],
                verifiedSHA256: row["verified_sha256"],
                transferError: row["transfer_error"]
            )
        }
    }
}
