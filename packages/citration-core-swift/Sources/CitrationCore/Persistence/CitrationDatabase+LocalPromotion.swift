import Foundation
import GRDB

// MARK: - LocalLibraryPromotionReport

public struct LocalLibraryPromotionReport: Equatable, Sendable {
    public let promotedObjectCount: Int
    public let skippedObjectCount: Int
    public let remappedKeyCount: Int
}

public extension CitrationDatabase {
    func promoteLocalLibrary(to targetIdentity: ZoteroLibraryIdentity, targetName: String?) throws
        -> LocalLibraryPromotionReport
    {
        guard
            let sourceLibraryID = try libraryDatabaseID(identity: .init(type: "local", remoteID: 0))
        else {
            return LocalLibraryPromotionReport(promotedObjectCount: 0, skippedObjectCount: 0, remappedKeyCount: 0)
        }
        let targetLibraryID = try upsertLibrary(identity: targetIdentity, name: targetName)
        guard sourceLibraryID != targetLibraryID else {
            return LocalLibraryPromotionReport(promotedObjectCount: 0, skippedObjectCount: 0, remappedKeyCount: 0)
        }
        return try databaseQueue.write { database in
            let sourceObjects = try Self.promotionObjects(libraryID: sourceLibraryID, database: database)
            let plan = try Self.promotionPlan(
                objects: sourceObjects,
                targetLibraryID: targetLibraryID,
                database: database
            )
            let counts = try Self.executePromotion(
                objects: sourceObjects,
                plan: plan,
                targetLibraryID: targetLibraryID,
                database: database
            )
            try Self.copyLocalState(
                keyMap: plan.keyMap,
                sourceLibraryID: sourceLibraryID,
                targetLibraryID: targetLibraryID,
                database: database
            )
            return LocalLibraryPromotionReport(
                promotedObjectCount: counts.promoted,
                skippedObjectCount: counts.skipped,
                remappedKeyCount: plan.remappedCount
            )
        }
    }

    private func libraryDatabaseID(identity: ZoteroLibraryIdentity) throws -> Int64? {
        try databaseQueue.read { database in
            try Int64.fetchOne(
                database,
                sql: "SELECT id FROM libraries WHERE remote_type = ? AND remote_id = ?",
                arguments: [identity.type, identity.remoteID]
            )
        }
    }

    private static func promotionObjects(libraryID: Int64, database: Database) throws -> [PromotionObject] {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT object.object_kind, object.object_key, object.object_type,
                   object.current_json, identity.app_uuid, identity.created_at, identity.updated_at
            FROM zotero_objects object
            LEFT JOIN app_object_identity identity
              ON identity.library_id = object.library_id
             AND identity.object_kind = object.object_kind
             AND identity.object_key = object.object_key
            WHERE object.library_id = ? AND object.object_kind IN ('collection', 'item')
                AND object.is_deleted = 0
            ORDER BY CASE object.object_kind WHEN 'collection' THEN 0 ELSE 1 END, object.object_key
            """,
            arguments: [libraryID]
        )
        var objects = [PromotionObject]()
        objects.reserveCapacity(rows.count)
        for row in rows {
            let currentData: Data = row["current_json"]
            let kind = ZoteroObjectKind(rawValue: row["object_kind"])
            let key: String = row["object_key"]
            let storedUUID: String? = row["app_uuid"]
            let timestamp = Date().timeIntervalSince1970
            let appUUID = storedUUID ?? UUID().uuidString
            let createdAt: Double = row["created_at"] ?? timestamp
            let updatedAt: Double = row["updated_at"] ?? timestamp
            if storedUUID == nil {
                try database.execute(
                    sql: """
                    INSERT INTO app_object_identity (
                        library_id, object_kind, object_key, app_uuid, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT (library_id, object_kind, object_key) DO NOTHING
                    """,
                    arguments: [libraryID, kind.rawValue, key, appUUID, createdAt, updatedAt]
                )
            }
            try objects.append(PromotionObject(
                kind: kind,
                key: key,
                objectType: row["object_type"],
                current: ZoteroJSON.decode(currentData),
                appUUID: appUUID,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        return objects
    }

    private static func promotionPlan(
        objects: [PromotionObject],
        targetLibraryID: Int64,
        database: Database
    ) throws -> PromotionPlan {
        var used = try Set(String.fetchAll(
            database,
            sql: "SELECT object_key FROM zotero_objects WHERE library_id = ?",
            arguments: [targetLibraryID]
        ))
        var keyMap = [String: String]()
        var skipKeys = Set<String>()
        var remappedCount = 0
        for object in objects {
            if let target = try targetIdentity(appUUID: object.appUUID, libraryID: targetLibraryID, database: database) {
                keyMap[object.key] = target.key
                if target.updatedAt >= object.updatedAt {
                    skipKeys.insert(object.key)
                }
                continue
            }
            var key = object.key
            if !ZoteroObjectKey.isValid(key) || used.contains(key) {
                key = availableKey(kind: object.kind, sourceKey: object.key, used: used)
                remappedCount += 1
            }
            keyMap[object.key] = key
            used.insert(key)
        }
        return PromotionPlan(keyMap: keyMap, skipKeys: skipKeys, remappedCount: remappedCount)
    }

    private static func targetIdentity(
        appUUID: String,
        libraryID: Int64,
        database: Database
    ) throws -> PromotionTargetIdentity? {
        try Row.fetchOne(
            database,
            sql: """
            SELECT object_key, updated_at FROM app_object_identity
            WHERE library_id = ? AND app_uuid = ?
            """,
            arguments: [libraryID, appUUID]
        ).map { PromotionTargetIdentity(key: $0["object_key"], updatedAt: $0["updated_at"]) }
    }

    private static func availableKey(kind: ZoteroObjectKind, sourceKey: String, used: Set<String>) -> String {
        for attempt in 0 ... 1000 {
            let candidate = ZoteroObjectKey.deterministic(
                namespace: "promote-\(kind.rawValue)-\(attempt)",
                value: sourceKey
            )
            if !used.contains(candidate) {
                return candidate
            }
        }
        return ZoteroObjectKey.random()
    }

    private static func executePromotion(
        objects: [PromotionObject],
        plan: PromotionPlan,
        targetLibraryID: Int64,
        database: Database
    ) throws -> (promoted: Int, skipped: Int) {
        var promoted = 0
        var skipped = 0
        for object in objects {
            guard !plan.skipKeys.contains(object.key) else {
                skipped += 1
                continue
            }
            let targetKey = plan.keyMap[object.key] ?? object.key
            let current = rewrite(object.current, keyMap: plan.keyMap, targetKey: targetKey)
            let stored = try promotedObject(
                source: object,
                targetKey: targetKey,
                current: current,
                targetLibraryID: targetLibraryID,
                database: database
            )
            try upsert(object: stored, libraryID: targetLibraryID, database: database)
            try updatePromotionProjection(stored, libraryID: targetLibraryID, database: database)
            try upsertPromotionIdentity(
                object,
                targetKey: targetKey,
                targetLibraryID: targetLibraryID,
                database: database
            )
            promoted += 1
        }
        return (promoted, skipped)
    }

    private static func promotedObject(
        source: PromotionObject,
        targetKey: String,
        current: JSONValue,
        targetLibraryID: Int64,
        database: Database
    ) throws -> ZoteroStoredObject {
        let existing = try fetchStoredObject(
            libraryID: targetLibraryID,
            kind: source.kind,
            key: targetKey,
            database: database
        )
        let version = existing?.version ?? 0
        return ZoteroStoredObject(
            kind: source.kind,
            key: targetKey,
            version: version,
            objectType: source.objectType,
            current: rewriteVersion(current, version: version),
            pristine: existing?.pristine ?? rewriteVersion(current, version: version),
            syncState: .dirty
        )
    }

    private static func updatePromotionProjection(
        _ object: ZoteroStoredObject,
        libraryID: Int64,
        database: Database
    ) throws {
        let raw = try ZoteroRawObject(rawValue: object.current)
        if object.kind == .collection {
            try upsertCollectionProjection(object: raw, libraryID: libraryID, database: database)
        } else {
            try replaceItemProjection(object: raw, libraryID: libraryID, database: database)
        }
    }

    private static func upsertPromotionIdentity(
        _ object: PromotionObject,
        targetKey: String,
        targetLibraryID: Int64,
        database: Database
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO app_object_identity (
                library_id, object_kind, object_key, app_uuid, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (library_id, object_kind, object_key) DO UPDATE SET
                app_uuid = excluded.app_uuid, updated_at = excluded.updated_at
            """,
            arguments: [
                targetLibraryID,
                object.kind.rawValue,
                targetKey,
                object.appUUID,
                object.createdAt,
                object.updatedAt,
            ]
        )
    }

    private static func rewrite(_ value: JSONValue, keyMap: [String: String], targetKey: String) -> JSONValue {
        guard var envelope = value.objectValue else {
            return value
        }
        envelope["key"] = .string(targetKey)
        envelope["version"] = .integer(0)
        if var data = envelope["data"]?.objectValue {
            data["key"] = .string(targetKey)
            data["version"] = .integer(0)
            rewriteKeyField("parentItem", in: &data, keyMap: keyMap)
            rewriteKeyField("parentCollection", in: &data, keyMap: keyMap)
            if let collections = data["collections"]?.arrayValue {
                data["collections"] = .array(collections.map { value in
                    value.stringValue.flatMap { keyMap[$0] }.map(JSONValue.string) ?? value
                })
            }
            if let relations = data["relations"] {
                data["relations"] = rewriteRelationValue(relations, keyMap: keyMap)
            }
            envelope["data"] = .object(data)
        }
        return .object(envelope)
    }

    private static func rewriteKeyField(
        _ field: String,
        in data: inout [String: JSONValue],
        keyMap: [String: String]
    ) {
        guard let key = data[field]?.stringValue, let mapped = keyMap[key] else {
            return
        }
        data[field] = .string(mapped)
    }

    private static func rewriteRelationValue(_ value: JSONValue, keyMap: [String: String]) -> JSONValue {
        switch value {
        case let .string(text):
            var result = text
            for (source, target) in keyMap {
                result = result.replacingOccurrences(of: "/items/\(source)", with: "/items/\(target)")
            }
            return .string(result)

        case let .array(values):
            return .array(values.map { rewriteRelationValue($0, keyMap: keyMap) })

        case let .object(values):
            return .object(values.mapValues { rewriteRelationValue($0, keyMap: keyMap) })

        default:
            return value
        }
    }

    private static func rewriteVersion(_ value: JSONValue, version: Int64) -> JSONValue {
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

// MARK: - PromotionObject

private struct PromotionObject {
    let kind: ZoteroObjectKind
    let key: String
    let objectType: String?
    let current: JSONValue
    let appUUID: String
    let createdAt: Double
    let updatedAt: Double
}

// MARK: - PromotionPlan

private struct PromotionPlan {
    let keyMap: [String: String]
    let skipKeys: Set<String>
    let remappedCount: Int
}

// MARK: - PromotionTargetIdentity

private struct PromotionTargetIdentity {
    let key: String
    let updatedAt: Double
}
