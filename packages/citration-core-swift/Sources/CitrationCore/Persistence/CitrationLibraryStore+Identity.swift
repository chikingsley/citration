import Foundation
import GRDB

extension CitrationLibraryStore {
    func objectKey(for uuid: UUID, kind: ZoteroObjectKind? = nil) throws -> String? {
        try database.databaseQueue.read { database in
            if let kind {
                return try String.fetchOne(
                    database,
                    sql: """
                    SELECT object_key FROM app_object_identity
                    WHERE library_id = ? AND app_uuid = ? AND object_kind = ?
                    """,
                    arguments: [libraryID, uuid.uuidString, kind.rawValue]
                )
            }
            return try String.fetchOne(
                database,
                sql: "SELECT object_key FROM app_object_identity WHERE library_id = ? AND app_uuid = ?",
                arguments: [libraryID, uuid.uuidString]
            )
        }
    }

    func appUUID(for key: String, kind: ZoteroObjectKind? = nil) throws -> UUID? {
        try database.databaseQueue.read { database in
            let value: String? = if let kind {
                try String.fetchOne(
                    database,
                    sql: """
                    SELECT app_uuid FROM app_object_identity
                    WHERE library_id = ? AND object_key = ? AND object_kind = ?
                    """,
                    arguments: [libraryID, key, kind.rawValue]
                )
            } else {
                try String.fetchOne(
                    database,
                    sql: "SELECT app_uuid FROM app_object_identity WHERE library_id = ? AND object_key = ?",
                    arguments: [libraryID, key]
                )
            }
            return value.flatMap(UUID.init(uuidString:))
        }
    }

    func upsertIdentity(
        uuid: UUID,
        kind: ZoteroObjectKind,
        key: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) throws {
        try database.databaseQueue.write { database in
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
                    createdAt.timeIntervalSince1970,
                    updatedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func markDeleted(kind: ZoteroObjectKind, key: String) throws {
        try database.markLocalDeletion(kind: kind, key: key, libraryID: libraryID)
    }
}
