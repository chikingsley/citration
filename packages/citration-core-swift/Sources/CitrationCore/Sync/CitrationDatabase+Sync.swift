import Foundation
import GRDB

public extension CitrationDatabase {
    func libraryVersion(identity: ZoteroLibraryIdentity) throws -> Int64 {
        try databaseQueue.read { database in
            try Int64.fetchOne(
                database,
                sql: "SELECT current_version FROM libraries WHERE remote_type = ? AND remote_id = ?",
                arguments: [identity.type, identity.remoteID]
            ) ?? 0
        }
    }

    func setLibraryVersion(_ version: Int64, libraryID: Int64) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                UPDATE libraries SET current_version = ?, updated_at = ? WHERE id = ?
                """,
                arguments: [version, Date().timeIntervalSince1970, libraryID]
            )
        }
    }

    func storeRemoteSearches(_ objects: [ZoteroRawObject], libraryID: Int64) throws {
        try storeRemoteVersionedObjects(objects, kind: .search, libraryID: libraryID)
    }

    func storeRemoteSettings(_ value: JSONValue, libraryID: Int64) throws {
        guard let settings = value.objectValue else {
            throw ZoteroTransportError.invalidResponse
        }
        let objects = settings.map { key, value -> ZoteroStoredObject in
            let version = value.objectValue?["version"]?.integerValue ?? 0
            return ZoteroStoredObject(
                kind: .setting,
                key: key,
                version: version,
                current: value
            )
        }
        try storeRemoteObjects(objects, libraryID: libraryID)
    }

    func storeRemoteGroups(_ groups: [JSONValue], libraryID: Int64) throws {
        let objects = groups.compactMap { group -> ZoteroStoredObject? in
            guard
                let data = group.objectValue,
                let id = data["id"]?.integerValue ?? data["data"]?.objectValue?["id"]?.integerValue
            else {
                return nil
            }
            let version = data["version"]?.integerValue ?? data["data"]?.objectValue?["version"]?.integerValue ?? 0
            return ZoteroStoredObject(
                kind: ZoteroObjectKind(rawValue: "group"),
                key: String(id),
                version: version,
                current: group
            )
        }
        try storeRemoteObjects(objects, libraryID: libraryID)
    }

    func ensureAppIdentities(
        collections: [ZoteroRawObject],
        items: [ZoteroRawObject],
        libraryID: Int64
    ) throws {
        try databaseQueue.write { database in
            for (kind, objects) in [(ZoteroObjectKind.collection, collections), (.item, items)] {
                for object in objects {
                    guard let key = object.key else {
                        continue
                    }
                    let createdAt = Self.remoteDate("dateAdded", object: object) ?? .now
                    let updatedAt = Self.remoteDate("dateModified", object: object) ?? createdAt
                    try database.execute(
                        sql: """
                        INSERT INTO app_object_identity (
                            library_id, object_kind, object_key, app_uuid, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT (library_id, object_kind, object_key) DO UPDATE SET
                            updated_at = excluded.updated_at
                        """,
                        arguments: [
                            libraryID,
                            kind.rawValue,
                            key,
                            UUID().uuidString,
                            createdAt.timeIntervalSince1970,
                            updatedAt.timeIntervalSince1970,
                        ]
                    )
                }
            }
        }
    }

    func applyRemoteDeletions(
        _ deletions: ZoteroDeletedObjects,
        version: Int64,
        libraryID: Int64
    ) throws {
        try databaseQueue.write { database in
            try Self.applyDeletedKeys(
                deletions.items,
                kind: .item,
                version: version,
                libraryID: libraryID,
                database: database
            )
            try Self.applyDeletedKeys(
                deletions.collections,
                kind: .collection,
                version: version,
                libraryID: libraryID,
                database: database
            )
            try Self.applyDeletedKeys(
                deletions.searches,
                kind: .search,
                version: version,
                libraryID: libraryID,
                database: database
            )
            try Self.applyDeletedKeys(
                deletions.settings,
                kind: .setting,
                version: version,
                libraryID: libraryID,
                database: database
            )
        }
    }

    private func storeRemoteVersionedObjects(
        _ objects: [ZoteroRawObject],
        kind: ZoteroObjectKind,
        libraryID: Int64
    ) throws {
        try storeRemoteObjects(
            objects.map { try ZoteroStoredObject(kind: kind, object: $0) },
            libraryID: libraryID
        )
    }

    private static func applyDeletedKeys(
        _ keys: [String],
        kind: ZoteroObjectKind,
        version: Int64,
        libraryID: Int64,
        database: Database
    ) throws {
        for key in keys {
            let existing = try fetchStoredObject(
                libraryID: libraryID,
                kind: kind,
                key: key,
                database: database
            )
            if let existing, existing.syncState == .dirty || existing.syncState == .failed {
                try recordRemoteDeletionConflict(
                    existing,
                    libraryID: libraryID,
                    database: database
                )
                continue
            }
            if existing == nil {
                try upsert(
                    object: ZoteroStoredObject(
                        kind: kind,
                        key: key,
                        version: version,
                        current: .object(["key": .string(key)]),
                        syncState: .synced,
                        isDeleted: true
                    ),
                    libraryID: libraryID,
                    database: database
                )
            } else {
                try database.execute(
                    sql: """
                    UPDATE zotero_objects SET object_version = ?, sync_state = 'synced',
                        is_deleted = 1, failure_message = NULL, updated_at = ?
                    WHERE library_id = ? AND object_kind = ? AND object_key = ?
                    """,
                    arguments: [version, Date().timeIntervalSince1970, libraryID, kind.rawValue, key]
                )
            }
            try deleteProjection(key: key, kind: kind, libraryID: libraryID, database: database)
        }
    }

    private static func recordRemoteDeletionConflict(
        _ existing: ZoteroStoredObject,
        libraryID: Int64,
        database: Database
    ) throws {
        let message = "Remote deletion conflicts with local changes"
        try recordSyncFailure(
            key: existing.key,
            kind: existing.kind,
            operation: "merge-conflict",
            message: message,
            details: conflictDetails(
                fields: ["<remote-deletion>"],
                base: existing.pristine,
                local: existing.current,
                remote: .null
            ),
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
                existing.kind.rawValue,
                existing.key,
            ]
        )
    }

    static func deleteProjection(
        key: String,
        kind: ZoteroObjectKind,
        libraryID: Int64,
        database: Database
    ) throws {
        if kind == .item {
            try database.execute(
                sql: "DELETE FROM item_projections WHERE library_id = ? AND item_key = ?",
                arguments: [libraryID, key]
            )
            try database.execute(
                sql: "DELETE FROM fulltext_content WHERE library_id = ? AND item_key = ?",
                arguments: [libraryID, key]
            )
            try database.execute(
                sql: "DELETE FROM library_search WHERE library_id = ? AND object_key = ?",
                arguments: [libraryID, key]
            )
        } else if kind == .collection {
            try database.execute(
                sql: "DELETE FROM collection_projections WHERE library_id = ? AND collection_key = ?",
                arguments: [libraryID, key]
            )
        }
    }

    private static func remoteDate(_ field: String, object: ZoteroRawObject) -> Date? {
        guard let value = object.data[field]?.stringValue else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
