import Foundation
import GRDB

extension CitrationDatabase {
    public func storeRemoteCollections(_ objects: [ZoteroRawObject], libraryID: Int64) throws {
        try storeCollections(objects, libraryID: libraryID, syncState: .synced)
    }

    public func storeLocalCollections(_ objects: [ZoteroRawObject], libraryID: Int64) throws {
        try storeCollections(objects, libraryID: libraryID, syncState: .dirty)
    }

    public func storeRemoteItems(_ objects: [ZoteroRawObject], libraryID: Int64) throws {
        try storeItems(objects, libraryID: libraryID, syncState: .synced)
    }

    public func storeLocalItems(_ objects: [ZoteroRawObject], libraryID: Int64) throws {
        try storeItems(objects, libraryID: libraryID, syncState: .dirty)
    }

    public func updateLocalItemFields(
        libraryID: Int64,
        key: String,
        updates: [ZoteroItemFieldUpdate],
        modifiedAt: Date = .now
    ) throws -> ZoteroStoredObject {
        let protectedFields = Set(["key", "version", "itemType", "dateAdded", "dateModified", "deleted"])
        for update in updates {
            guard
                !update.field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !protectedFields.contains(update.field)
            else {
                throw ZoteroItemEditingError.invalidField(update.field)
            }
        }

        return try databaseQueue.write { database in
            guard
                let existing = try Self.fetchStoredObject(
                    libraryID: libraryID,
                    kind: .item,
                    key: key,
                    database: database
                )
            else {
                throw ZoteroItemEditingError.itemNotFound
            }
            guard var envelope = existing.current.objectValue, var data = envelope["data"]?.objectValue else {
                throw ZoteroItemEditingError.malformedObject
            }

            for update in updates {
                data[update.field] = update.value
            }
            data["dateModified"] = .string(ISO8601DateFormatter().string(from: modifiedAt))
            data["key"] = .string(key)
            envelope["key"] = .string(key)
            envelope["data"] = .object(data)

            let rawObject = try ZoteroRawObject(rawValue: .object(envelope))
            let candidate = try ZoteroStoredObject(kind: .item, object: rawObject, syncState: .dirty)
            let persisted = try Self.upsertLocal(
                object: candidate,
                libraryID: libraryID,
                database: database
            )
            try Self.replaceItemProjection(
                object: ZoteroRawObject(rawValue: persisted.current),
                libraryID: libraryID,
                database: database
            )
            try database.notifyChanges(in: Table("item_projections"))
            return persisted
        }
    }

    private func storeCollections(
        _ objects: [ZoteroRawObject],
        libraryID: Int64,
        syncState: ZoteroSyncState
    ) throws {
        try databaseQueue.write { database in
            for object in objects {
                let storedObject = try ZoteroStoredObject(
                    kind: .collection,
                    object: object,
                    syncState: syncState
                )
                let persistedObject = try Self.persistLocalOrRemote(
                    storedObject,
                    syncState: syncState,
                    libraryID: libraryID,
                    database: database
                )
                try Self.upsertCollectionProjection(
                    object: ZoteroRawObject(rawValue: persistedObject.current),
                    libraryID: libraryID,
                    database: database
                )
            }
        }
    }

    private func storeItems(
        _ objects: [ZoteroRawObject],
        libraryID: Int64,
        syncState: ZoteroSyncState
    ) throws {
        try databaseQueue.write { database in
            for object in objects {
                let storedObject = try ZoteroStoredObject(kind: .item, object: object, syncState: syncState)
                let persistedObject = try Self.persistLocalOrRemote(
                    storedObject,
                    syncState: syncState,
                    libraryID: libraryID,
                    database: database
                )
                try Self.replaceItemProjection(
                    object: ZoteroRawObject(rawValue: persistedObject.current),
                    libraryID: libraryID,
                    database: database
                )
            }
            try database.notifyChanges(in: Table("item_projections"))
        }
    }

    private static func persistLocalOrRemote(
        _ object: ZoteroStoredObject,
        syncState: ZoteroSyncState,
        libraryID: Int64,
        database: Database
    ) throws -> ZoteroStoredObject {
        guard syncState == .dirty else {
            try upsert(object: object, libraryID: libraryID, database: database)
            return object
        }
        return try upsertLocal(object: object, libraryID: libraryID, database: database)
    }

    private static func upsertLocal(
        object: ZoteroStoredObject,
        libraryID: Int64,
        database: Database
    ) throws -> ZoteroStoredObject {
        guard
            let existing = try Row.fetchOne(
                database,
                sql: """
                SELECT object_version, pristine_json FROM zotero_objects
                WHERE library_id = ? AND object_kind = ? AND object_key = ?
                """,
                arguments: [libraryID, object.kind.rawValue, object.key]
            )
        else {
            try upsert(object: object, libraryID: libraryID, database: database)
            return object
        }
        let version: Int64 = existing["object_version"]
        let pristineData: Data = existing["pristine_json"]
        let persisted = try ZoteroStoredObject(
            kind: object.kind,
            key: object.key,
            version: version,
            objectType: object.objectType,
            current: versioned(object.current, version: version),
            pristine: ZoteroJSON.decode(pristineData),
            syncState: .dirty
        )
        try upsert(object: persisted, libraryID: libraryID, database: database)
        return persisted
    }

    private static func versioned(_ value: JSONValue, version: Int64) -> JSONValue {
        guard var envelope = value.objectValue else {
            return value
        }
        envelope["version"] = .integer(version)
        if var data = envelope["data"]?.objectValue {
            data["version"] = .integer(version)
            envelope["data"] = .object(data)
        }
        return .object(envelope)
    }
}
