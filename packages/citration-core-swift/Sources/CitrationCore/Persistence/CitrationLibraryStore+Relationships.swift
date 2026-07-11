import Foundation
import GRDB

public extension CitrationLibraryStore {
    func listRelationships(itemID: UUID?) throws -> [LibraryRelationship] {
        let itemKey = try itemID.flatMap { try objectKey(for: $0, kind: .item) }
        return try database.databaseQueue.read { database in
            var arguments: StatementArguments = [libraryID]
            var itemClause = ""
            if let itemKey {
                itemClause = "AND (source_item_key = ? OR target_item_key = ?)"
                arguments += [itemKey, itemKey]
            }
            return try Data.fetchAll(
                database,
                sql: """
                SELECT raw_json FROM app_relationships
                WHERE library_id = ? \(itemClause)
                ORDER BY relationship_kind, source_item_key, target_item_key
                """,
                arguments: arguments
            ).map { try JSONDecoder().decode(LibraryRelationship.self, from: $0) }
        }
    }

    func upsert(_ input: LibraryRelationship) throws -> LibraryRelationship {
        guard
            let sourceKey = try objectKey(for: input.sourceItemID, kind: .item),
            let targetKey = try objectKey(for: input.targetItemID, kind: .item)
        else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        var relationship = input
        if
            let existing = try listRelationships(itemID: input.sourceItemID).first(where: {
                $0.sourceItemID == input.sourceItemID
                    && $0.targetItemID == input.targetItemID
                    && $0.kind == input.kind
            })
        {
            relationship.id = existing.id
        }
        let data = try JSONEncoder().encode(relationship)
        try database.databaseQueue.write { database in
            try database.execute(
                sql: """
                INSERT INTO app_relationships (
                    library_id, relationship_id, source_item_key, target_item_key,
                    relationship_kind, confidence, note, raw_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (library_id, relationship_id) DO UPDATE SET
                    source_item_key = excluded.source_item_key,
                    target_item_key = excluded.target_item_key,
                    relationship_kind = excluded.relationship_kind,
                    confidence = excluded.confidence,
                    note = excluded.note,
                    raw_json = excluded.raw_json
                """,
                arguments: [
                    libraryID,
                    relationship.id.uuidString,
                    sourceKey,
                    targetKey,
                    relationship.kind.rawValue,
                    relationship.confidence,
                    relationship.note,
                    data,
                ]
            )
        }
        return relationship
    }

    func removeRelationships(itemIDs: [UUID]) throws {
        for itemID in Set(itemIDs) {
            guard let key = try objectKey(for: itemID, kind: .item) else {
                continue
            }
            try database.databaseQueue.write { database in
                try database.execute(
                    sql: """
                    DELETE FROM app_relationships
                    WHERE library_id = ? AND (source_item_key = ? OR target_item_key = ?)
                    """,
                    arguments: [libraryID, key, key]
                )
            }
        }
    }
}
