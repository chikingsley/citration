import Foundation
import GRDB

// MARK: - ZoteroConflictResolution

public enum ZoteroConflictResolution: Equatable, Sendable {
    case keepLocal
    case keepRemote
    case delete
}

// MARK: - ZoteroConflictResolutionError

public enum ZoteroConflictResolutionError: Error, Equatable, Sendable {
    case missingConflict
    case missingRemoteObject
}

public extension CitrationDatabase {
    func resolveConflict(
        kind: ZoteroObjectKind,
        key: String,
        resolution: ZoteroConflictResolution,
        libraryID: Int64
    ) throws {
        try databaseQueue.write { database in
            guard
                let local = try Self.fetchStoredObject(
                    libraryID: libraryID,
                    kind: kind,
                    key: key,
                    database: database
                ),
                let detailsData = try Data.fetchOne(
                    database,
                    sql: """
                    SELECT details_json FROM synchronization_failures
                    WHERE library_id = ? AND object_kind = ? AND object_key = ?
                        AND operation = 'merge-conflict' AND resolved_at IS NULL
                    ORDER BY id DESC LIMIT 1
                    """,
                    arguments: [libraryID, kind.rawValue, key]
                ),
                let details = try ZoteroJSON.decode(detailsData).objectValue
            else {
                throw ZoteroConflictResolutionError.missingConflict
            }
            let resolved = try Self.resolvedObject(
                local: local,
                remoteValue: details["remote"],
                resolution: resolution
            )
            try Self.upsert(object: resolved, libraryID: libraryID, database: database)
            try Self.updateProjectionAfterResolution(
                resolved,
                resolution: resolution,
                libraryID: libraryID,
                database: database
            )
            try Self.resolveSyncFailure(
                key: key,
                kind: kind,
                operation: "merge-conflict",
                libraryID: libraryID,
                database: database
            )
        }
    }

    private static func resolvedObject(
        local: ZoteroStoredObject,
        remoteValue: JSONValue?,
        resolution: ZoteroConflictResolution
    ) throws -> ZoteroStoredObject {
        guard let remoteValue, remoteValue != .null else {
            if case .keepRemote = resolution {
                return ZoteroStoredObject(
                    kind: local.kind,
                    key: local.key,
                    version: local.version,
                    objectType: local.objectType,
                    current: local.current,
                    pristine: local.pristine,
                    syncState: .synced,
                    isDeleted: true
                )
            }
            throw ZoteroConflictResolutionError.missingRemoteObject
        }
        let remote = try ZoteroStoredObject(
            kind: local.kind,
            object: ZoteroRawObject(rawValue: remoteValue)
        )
        switch resolution {
        case .keepRemote:
            return remote

        case .keepLocal:
            return ZoteroStoredObject(
                kind: local.kind,
                key: local.key,
                version: remote.version,
                objectType: local.objectType,
                current: localValue(local.current, withRemoteIdentityFrom: remote.current),
                pristine: remote.current,
                syncState: .dirty
            )

        case .delete:
            return ZoteroStoredObject(
                kind: local.kind,
                key: local.key,
                version: remote.version,
                objectType: local.objectType,
                current: local.current,
                pristine: remote.current,
                syncState: .deleted,
                isDeleted: true
            )
        }
    }

    private static func localValue(_ local: JSONValue, withRemoteIdentityFrom remote: JSONValue) -> JSONValue {
        guard var localEnvelope = local.objectValue, let remoteEnvelope = remote.objectValue else {
            return local
        }
        localEnvelope["key"] = remoteEnvelope["key"]
        localEnvelope["version"] = remoteEnvelope["version"]
        if var localData = localEnvelope["data"]?.objectValue, let remoteData = remoteEnvelope["data"]?.objectValue {
            localData["key"] = remoteData["key"]
            localData["version"] = remoteData["version"]
            localEnvelope["data"] = .object(localData)
        }
        return .object(localEnvelope)
    }

    private static func updateProjectionAfterResolution(
        _ object: ZoteroStoredObject,
        resolution: ZoteroConflictResolution,
        libraryID: Int64,
        database: Database
    ) throws {
        if object.isDeleted || resolution == .delete {
            try deleteProjection(key: object.key, kind: object.kind, libraryID: libraryID, database: database)
            return
        }
        let raw = try ZoteroRawObject(rawValue: object.current)
        if object.kind == .item {
            try replaceItemProjection(object: raw, libraryID: libraryID, database: database)
        } else if object.kind == .collection {
            try upsertCollectionProjection(object: raw, libraryID: libraryID, database: database)
        }
    }
}
