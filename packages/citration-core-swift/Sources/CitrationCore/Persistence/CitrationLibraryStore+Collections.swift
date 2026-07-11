import Foundation
import GRDB

extension CitrationLibraryStore {
    public func snapshot() throws -> LibraryCollectionSnapshot {
        try database.databaseQueue.read { database in
            let collections = try Row.fetchAll(
                database,
                sql: """
                SELECT collection.*, identity.app_uuid, identity.created_at, identity.updated_at,
                    parent_identity.app_uuid AS parent_uuid
                FROM collection_projections collection
                JOIN app_object_identity identity
                  ON identity.library_id = collection.library_id
                 AND identity.object_kind = 'collection'
                 AND identity.object_key = collection.collection_key
                LEFT JOIN app_object_identity parent_identity
                  ON parent_identity.library_id = collection.library_id
                 AND parent_identity.object_kind = 'collection'
                 AND parent_identity.object_key = collection.parent_collection_key
                WHERE collection.library_id = ?
                ORDER BY collection.name COLLATE NOCASE
                """,
                arguments: [libraryID]
            ).compactMap(Self.decodeCollection)
            let memberships = try Row.fetchAll(
                database,
                sql: """
                SELECT membership.*, collection_identity.app_uuid AS collection_uuid,
                    item_identity.app_uuid AS item_uuid
                FROM app_collection_memberships membership
                JOIN app_object_identity collection_identity
                  ON collection_identity.library_id = membership.library_id
                 AND collection_identity.object_key = membership.collection_key
                JOIN app_object_identity item_identity
                  ON item_identity.library_id = membership.library_id
                 AND item_identity.object_key = membership.item_key
                WHERE membership.library_id = ?
                ORDER BY membership.created_at
                """,
                arguments: [libraryID]
            ).compactMap(Self.decodeMembership)
            return LibraryCollectionSnapshot(collections: collections, memberships: memberships)
        }
    }

    public func createCollection(name: String, parentID: UUID?) throws -> LibraryCollection {
        let collection = LibraryCollection(name: name, parentID: parentID)
        let key = LegacyZoteroObjectFactory.collectionKey(for: collection.id)
        let parentKeys = try collectionIdentityMap()
        let object = try LegacyZoteroObjectFactory.collectionObject(
            collection,
            key: key,
            collectionKeys: parentKeys
        )
        try database.storeLocalCollections([object], libraryID: libraryID)
        try upsertIdentity(
            uuid: collection.id,
            kind: .collection,
            key: key,
            createdAt: collection.createdAt,
            updatedAt: collection.updatedAt
        )
        return try snapshot().collections.first { $0.id == collection.id } ?? collection
    }

    public func removeCollection(id: UUID) throws {
        let current = try snapshot()
        let ids = descendantIDs(of: id, in: current).union([id])
        for collectionID in ids {
            guard let key = try objectKey(for: collectionID, kind: .collection) else {
                continue
            }
            let itemKeys = try membershipItemKeys(collectionKey: key)
            for itemKey in itemKeys {
                try removeCollectionKey(key, fromItemKey: itemKey)
            }
            try markDeleted(kind: .collection, key: key)
        }
    }

    public func addItem(_ itemID: UUID, to collectionID: UUID) throws -> LibraryCollectionMembership {
        guard
            let itemKey = try objectKey(for: itemID, kind: .item),
            let collectionKey = try objectKey(for: collectionID, kind: .collection)
        else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        if let existing = try membership(itemID: itemID, collectionID: collectionID) {
            return existing
        }
        let membership = LibraryCollectionMembership(collectionID: collectionID, itemID: itemID)
        try insertMembership(membership, itemKey: itemKey, collectionKey: collectionKey)
        try addCollectionKey(collectionKey, toItemKey: itemKey)
        return try snapshot().memberships.first { $0.id == membership.id } ?? membership
    }

    public func removeItem(_ itemID: UUID, from collectionID: UUID) throws {
        guard
            let itemKey = try objectKey(for: itemID, kind: .item),
            let collectionKey = try objectKey(for: collectionID, kind: .collection)
        else {
            return
        }
        try database.databaseQueue.write { database in
            try database.execute(
                sql: """
                DELETE FROM app_collection_memberships
                WHERE library_id = ? AND collection_key = ? AND item_key = ?
                """,
                arguments: [libraryID, collectionKey, itemKey]
            )
        }
        try removeCollectionKey(collectionKey, fromItemKey: itemKey)
    }

    public func removeItems(ids: [UUID]) throws {
        for id in Set(ids) {
            guard let key = try objectKey(for: id, kind: .item) else {
                continue
            }
            try database.databaseQueue.write { database in
                try database.execute(
                    sql: "DELETE FROM app_collection_memberships WHERE library_id = ? AND item_key = ?",
                    arguments: [libraryID, key]
                )
            }
        }
    }

    private func collectionIdentityMap() throws -> [UUID: String] {
        let current = try snapshot().collections
        return try Dictionary(uniqueKeysWithValues: current.compactMap { collection in
            try objectKey(for: collection.id, kind: .collection).map { (collection.id, $0) }
        })
    }

    private func membership(itemID: UUID, collectionID: UUID) throws -> LibraryCollectionMembership? {
        try snapshot().memberships.first {
            $0.itemID == itemID && $0.collectionID == collectionID
        }
    }

    private func insertMembership(
        _ membership: LibraryCollectionMembership,
        itemKey: String,
        collectionKey: String
    ) throws {
        try database.databaseQueue.write { database in
            try database.execute(
                sql: """
                INSERT INTO app_collection_memberships (
                    library_id, collection_key, item_key, membership_uuid, created_at
                ) VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    libraryID,
                    collectionKey,
                    itemKey,
                    membership.id.uuidString,
                    membership.createdAt.timeIntervalSince1970,
                ]
            )
        }
    }

    private func addCollectionKey(_ collectionKey: String, toItemKey itemKey: String) throws {
        var keys = try itemCollectionKeys(itemKey: itemKey)
        if !keys.contains(collectionKey) {
            keys.append(collectionKey)
        }
        try setCollectionKeys(keys, itemKey: itemKey)
    }

    private func removeCollectionKey(_ collectionKey: String, fromItemKey itemKey: String) throws {
        let keys = try itemCollectionKeys(itemKey: itemKey).filter { $0 != collectionKey }
        try setCollectionKeys(keys, itemKey: itemKey)
    }

    private func setCollectionKeys(_ keys: [String], itemKey: String) throws {
        guard let stored = try database.fetchObject(libraryID: libraryID, kind: .item, key: itemKey) else {
            return
        }
        var root = stored.current.objectValue ?? [:]
        var data = root["data"]?.objectValue ?? [:]
        data["collections"] = .array(keys.map(JSONValue.string))
        data["version"] = .integer(0)
        root["data"] = .object(data)
        root["version"] = .integer(0)
        try database.storeLocalItems(
            [ZoteroRawObject(rawValue: .object(root))],
            libraryID: libraryID
        )
    }

    private func itemCollectionKeys(itemKey: String) throws -> [String] {
        try database.databaseQueue.read { database in
            try String.fetchAll(
                database,
                sql: """
                SELECT collection_key FROM app_collection_memberships
                WHERE library_id = ? AND item_key = ? ORDER BY created_at
                """,
                arguments: [libraryID, itemKey]
            )
        }
    }

    private func membershipItemKeys(collectionKey: String) throws -> [String] {
        try database.databaseQueue.read { database in
            try String.fetchAll(
                database,
                sql: """
                SELECT item_key FROM app_collection_memberships
                WHERE library_id = ? AND collection_key = ?
                """,
                arguments: [libraryID, collectionKey]
            )
        }
    }

    private func descendantIDs(of id: UUID, in snapshot: LibraryCollectionSnapshot) -> Set<UUID> {
        let children = snapshot.collections.filter { $0.parentID == id }.map(\.id)
        return children.reduce(into: Set(children)) { result, child in
            result.formUnion(descendantIDs(of: child, in: snapshot))
        }
    }

    private static func decodeCollection(_ row: Row) -> LibraryCollection? {
        let uuidText: String = row["app_uuid"]
        guard let id = UUID(uuidString: uuidText) else {
            return nil
        }
        let parentText: String? = row["parent_uuid"]
        return LibraryCollection(
            id: id,
            name: row["name"],
            parentID: parentText.flatMap(UUID.init(uuidString:)),
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"])
        )
    }

    private static func decodeMembership(_ row: Row) -> LibraryCollectionMembership? {
        guard
            let id = UUID(uuidString: row["membership_uuid"]),
            let collectionID = UUID(uuidString: row["collection_uuid"]),
            let itemID = UUID(uuidString: row["item_uuid"])
        else {
            return nil
        }
        return LibraryCollectionMembership(
            id: id,
            collectionID: collectionID,
            itemID: itemID,
            createdAt: Date(timeIntervalSince1970: row["created_at"])
        )
    }
}
