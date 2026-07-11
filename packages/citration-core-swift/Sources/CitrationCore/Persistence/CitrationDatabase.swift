import Foundation
import GRDB

// MARK: - ZoteroLibraryIdentity

public struct ZoteroLibraryIdentity: Hashable, Sendable {
    // MARK: Lifecycle

    public init(type: String, remoteID: Int64) {
        self.type = type
        self.remoteID = remoteID
    }

    // MARK: Public

    public let type: String
    public let remoteID: Int64
}

// MARK: - ZoteroObjectKind

public struct ZoteroObjectKind: Hashable, RawRepresentable, Sendable {
    // MARK: Lifecycle

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    // MARK: Public

    public static let collection: Self = .init(rawValue: "collection")
    public static let deleted: Self = .init(rawValue: "deleted")
    public static let fulltext: Self = .init(rawValue: "fulltext")
    public static let item: Self = .init(rawValue: "item")
    public static let search: Self = .init(rawValue: "search")
    public static let setting: Self = .init(rawValue: "setting")

    public let rawValue: String
}

// MARK: - ZoteroSyncState

public enum ZoteroSyncState: String, Sendable {
    case synced
    case dirty
    case deleted
    case failed
}

// MARK: - ZoteroStoredObject

public struct ZoteroStoredObject: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        kind: ZoteroObjectKind,
        key: String,
        version: Int64,
        objectType: String? = nil,
        current: JSONValue,
        pristine: JSONValue? = nil,
        syncState: ZoteroSyncState = .synced,
        isDeleted: Bool = false,
        failureMessage: String? = nil
    ) {
        self.kind = kind
        self.key = key
        self.version = version
        self.objectType = objectType
        self.current = current
        self.pristine = pristine ?? current
        self.syncState = syncState
        self.isDeleted = isDeleted
        self.failureMessage = failureMessage
    }

    public init(kind: ZoteroObjectKind, object: ZoteroRawObject) throws {
        guard let key = object.key else {
            throw CitrationDatabaseError.missingObjectKey
        }
        self.init(
            kind: kind,
            key: key,
            version: object.version ?? 0,
            objectType: object.itemType,
            current: object.rawValue
        )
    }

    // MARK: Public

    public let kind: ZoteroObjectKind
    public let key: String
    public let version: Int64
    public let objectType: String?
    public let current: JSONValue
    public let pristine: JSONValue
    public let syncState: ZoteroSyncState
    public let isDeleted: Bool
    public let failureMessage: String?
}

// MARK: - CitrationDatabaseError

public enum CitrationDatabaseError: Error, Equatable, Sendable {
    case invalidLibraryIdentity
    case invalidObjectKey
    case missingObjectKey
    case unknownSyncState(String)
}

// MARK: - CitrationDatabase

public final class CitrationDatabase: @unchecked Sendable {
    // MARK: Lifecycle

    public init(at databaseURL: URL) throws {
        guard databaseURL.isFileURL else {
            throw CitrationDatabaseError.invalidLibraryIdentity
        }

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA journal_mode = WAL")
            try database.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        databaseQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try Self.migrator.migrate(databaseQueue)
    }

    // MARK: Public

    public func upsertLibrary(
        identity: ZoteroLibraryIdentity,
        name: String? = nil,
        currentVersion: Int64 = 0
    ) throws -> Int64 {
        guard !identity.type.isEmpty, identity.remoteID >= 0 else {
            throw CitrationDatabaseError.invalidLibraryIdentity
        }

        return try databaseQueue.write { database in
            try database.execute(
                sql: """
                INSERT INTO libraries (remote_type, remote_id, name, current_version, created_at, updated_at)
                VALUES (?, ?, ?, ?, unixepoch('subsec'), unixepoch('subsec'))
                ON CONFLICT (remote_type, remote_id) DO UPDATE SET
                    name = excluded.name,
                    current_version = MAX(libraries.current_version, excluded.current_version),
                    updated_at = excluded.updated_at
                """,
                arguments: [identity.type, identity.remoteID, name, currentVersion]
            )

            guard
                let libraryID = try Int64.fetchOne(
                    database,
                    sql: "SELECT id FROM libraries WHERE remote_type = ? AND remote_id = ?",
                    arguments: [identity.type, identity.remoteID]
                )
            else {
                throw CitrationDatabaseError.invalidLibraryIdentity
            }
            return libraryID
        }
    }

    public func storeRemoteObjects(_ objects: [ZoteroStoredObject], libraryID: Int64) throws {
        try databaseQueue.write { database in
            for object in objects {
                guard !object.key.isEmpty else {
                    throw CitrationDatabaseError.invalidObjectKey
                }
                try Self.upsert(object: object, libraryID: libraryID, database: database)
            }
        }
    }

    public func fetchObject(
        libraryID: Int64,
        kind: ZoteroObjectKind,
        key: String
    ) throws -> ZoteroStoredObject? {
        try databaseQueue.read { database in
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
            guard let syncState = ZoteroSyncState(rawValue: stateValue) else {
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
                syncState: syncState,
                isDeleted: row["is_deleted"],
                failureMessage: row["failure_message"]
            )
        }
    }

    public func objectCount(libraryID: Int64, kind: ZoteroObjectKind? = nil) throws -> Int {
        try databaseQueue.read { database in
            if let kind {
                return try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM zotero_objects WHERE library_id = ? AND object_kind = ?",
                    arguments: [libraryID, kind.rawValue]
                ) ?? 0
            }
            return try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM zotero_objects WHERE library_id = ?",
                arguments: [libraryID]
            ) ?? 0
        }
    }

    public func integrityCheck() throws -> String {
        try databaseQueue.read { database in
            try String.fetchOne(database, sql: "PRAGMA integrity_check") ?? "missing result"
        }
    }

    public func schemaObjects() throws -> Set<String> {
        try databaseQueue.read { database in
            let names = try String.fetchAll(
                database,
                sql: """
                SELECT name FROM sqlite_schema
                WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'
                """
            )
            return Set(names)
        }
    }

    // MARK: Private

    private let databaseQueue: DatabaseQueue

    private static func upsert(
        object: ZoteroStoredObject,
        libraryID: Int64,
        database: Database
    ) throws {
        let currentData = try ZoteroJSON.encode(object.current)
        let pristineData = try ZoteroJSON.encode(object.pristine)
        try database.execute(
            sql: """
            INSERT INTO zotero_objects (
                library_id, object_kind, object_key, object_version, object_type,
                current_json, pristine_json, sync_state, is_deleted, failure_message, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, unixepoch('subsec'))
            ON CONFLICT (library_id, object_kind, object_key) DO UPDATE SET
                object_version = excluded.object_version,
                object_type = excluded.object_type,
                current_json = excluded.current_json,
                pristine_json = excluded.pristine_json,
                sync_state = excluded.sync_state,
                is_deleted = excluded.is_deleted,
                failure_message = excluded.failure_message,
                updated_at = excluded.updated_at
            """,
            arguments: [
                libraryID,
                object.kind.rawValue,
                object.key,
                object.version,
                object.objectType,
                currentData,
                pristineData,
                object.syncState.rawValue,
                object.isDeleted,
                object.failureMessage,
            ]
        )
    }
}
