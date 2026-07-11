import Foundation
import GRDB

public extension CitrationLibraryStore {
    func progress(for attachmentKey: String) throws -> ReaderProgress? {
        try database.databaseQueue.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: "SELECT item_key, locator_json FROM reader_state WHERE library_id = ? AND item_key = ?",
                    arguments: [libraryID, attachmentKey]
                )
            else {
                return nil
            }
            return try Self.decodeProgress(row)
        }
    }

    func listProgress(itemID: UUID?) throws -> [ReaderProgress] {
        let itemKey = try itemID.flatMap { try objectKey(for: $0, kind: .item) }
        return try database.databaseQueue.read { database in
            var arguments: StatementArguments = [libraryID]
            var itemClause = ""
            if let itemKey {
                itemClause = "AND attachment.parent_item_key = ?"
                arguments += [itemKey]
            }
            return try Row.fetchAll(
                database,
                sql: """
                SELECT state.item_key, state.locator_json FROM reader_state state
                JOIN attachment_projections attachment
                  ON attachment.library_id = state.library_id
                 AND attachment.item_key = state.item_key
                WHERE state.library_id = ? \(itemClause)
                ORDER BY state.updated_at DESC
                """,
                arguments: arguments
            ).map(Self.decodeProgress)
        }
    }

    func upsert(_ input: ReaderProgress) throws -> ReaderProgress {
        var progress = input
        progress.updatedAt = .now
        let data = try JSONEncoder().encode(progress)
        try database.databaseQueue.write { database in
            try database.execute(
                sql: """
                INSERT INTO reader_state (
                    library_id, item_key, locator_json, fraction_complete, selected_page, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT (library_id, item_key) DO UPDATE SET
                    locator_json = excluded.locator_json,
                    fraction_complete = excluded.fraction_complete,
                    selected_page = excluded.selected_page,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    libraryID,
                    progress.attachmentKey,
                    data,
                    progress.fractionComplete ?? 0,
                    progress.location.selectedPageNumber,
                    progress.updatedAt.timeIntervalSince1970,
                ]
            )
        }
        return progress
    }

    func remove(attachmentKey: String) throws {
        try database.databaseQueue.write { database in
            try database.execute(
                sql: "DELETE FROM reader_state WHERE library_id = ? AND item_key = ?",
                arguments: [libraryID, attachmentKey]
            )
        }
    }

    func removeProgress(itemIDs: [UUID]) throws {
        for itemID in Set(itemIDs) {
            guard let itemKey = try objectKey(for: itemID, kind: .item) else {
                continue
            }
            try database.databaseQueue.write { database in
                try database.execute(
                    sql: """
                    DELETE FROM reader_state
                    WHERE library_id = ? AND item_key IN (
                        SELECT item_key FROM attachment_projections
                        WHERE library_id = ? AND parent_item_key = ?
                    )
                    """,
                    arguments: [libraryID, libraryID, itemKey]
                )
            }
        }
    }

    private static func decodeProgress(_ row: Row) throws -> ReaderProgress {
        let data: Data = row["locator_json"]
        var progress = try JSONDecoder().decode(ReaderProgress.self, from: data)
        progress.attachmentKey = row["item_key"]
        return progress
    }
}

private extension ReaderLocation {
    var selectedPageNumber: Int? {
        guard case let .page(number) = self else {
            return nil
        }
        return number
    }
}
