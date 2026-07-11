import GRDB

// MARK: - CitrationDatabaseObservation

public final class CitrationDatabaseObservation: Sendable {
    // MARK: Lifecycle

    init(_ cancellable: AnyDatabaseCancellable) {
        self.cancellable = cancellable
    }

    // MARK: Public

    public func cancel() {
        cancellable.cancel()
    }

    // MARK: Private

    private let cancellable: AnyDatabaseCancellable
}

extension CitrationDatabase {
    public func observeLibraryItems(
        libraryID: Int64,
        onError: @escaping @Sendable (any Error) -> Void,
        onChange: @escaping @Sendable ([ZoteroLibraryItemSummary]) -> Void
    ) -> CitrationDatabaseObservation {
        let observation = DatabaseRegionObservation(tracking: Table("item_projections"))
        let cancellable = observation.start(
            in: databaseQueue,
            onError: onError,
            onChange: { database in
                do {
                    try onChange(Self.fetchLibraryItemSummaries(libraryID: libraryID, database: database))
                } catch {
                    onError(error)
                }
            }
        )

        do {
            try onChange(databaseQueue.read { database in
                try Self.fetchLibraryItemSummaries(libraryID: libraryID, database: database)
            })
        } catch {
            onError(error)
        }
        return CitrationDatabaseObservation(cancellable)
    }

    private static func fetchLibraryItemSummaries(
        libraryID: Int64,
        database: Database
    ) throws -> [ZoteroLibraryItemSummary] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT item_key, item_type, title, date_text, publication_title, parent_item_key
            FROM item_projections
            WHERE library_id = ?
            ORDER BY title COLLATE NOCASE, item_key
            """,
            arguments: [libraryID]
        ).map { row in
            ZoteroLibraryItemSummary(
                key: row["item_key"],
                itemType: row["item_type"],
                title: row["title"],
                date: row["date_text"],
                publicationTitle: row["publication_title"],
                parentItemKey: row["parent_item_key"]
            )
        }
    }
}
