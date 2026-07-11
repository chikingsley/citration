import Dispatch
import GRDB

// MARK: - ZoteroSavedSearchSummary

public struct ZoteroSavedSearchSummary: Hashable, Sendable {
    // MARK: Lifecycle

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }

    // MARK: Public

    public let key: String
    public let name: String
}

// MARK: - ZoteroLibraryNavigationSnapshot

public struct ZoteroLibraryNavigationSnapshot: Hashable, Sendable {
    // MARK: Lifecycle

    public init(savedSearches: [ZoteroSavedSearchSummary], deletedItemCount: Int) {
        self.savedSearches = savedSearches
        self.deletedItemCount = deletedItemCount
    }

    // MARK: Public

    public let savedSearches: [ZoteroSavedSearchSummary]
    public let deletedItemCount: Int
}

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

public extension CitrationDatabase {
    func observeLibraryItems(
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

    func fetchLibraryNavigationSnapshot(libraryID: Int64) throws -> ZoteroLibraryNavigationSnapshot {
        try databaseQueue.read { database in
            try Self.fetchLibraryNavigationSnapshot(libraryID: libraryID, database: database)
        }
    }

    func observeLibraryNavigation(
        libraryID: Int64,
        onError: @escaping @Sendable (any Error) -> Void,
        onChange: @escaping @Sendable (ZoteroLibraryNavigationSnapshot) -> Void
    ) -> CitrationDatabaseObservation {
        let observation = ValueObservation.tracking { database in
            try Self.fetchLibraryNavigationSnapshot(libraryID: libraryID, database: database)
        }
        let cancellable = observation.start(
            in: databaseQueue,
            scheduling: .async(onQueue: DispatchQueue(label: "CitrationCore.NavigationObservation")),
            onError: onError,
            onChange: onChange
        )
        return CitrationDatabaseObservation(cancellable)
    }

    private static func fetchLibraryNavigationSnapshot(
        libraryID: Int64,
        database: Database
    ) throws -> ZoteroLibraryNavigationSnapshot {
        _ = try Double.fetchOne(
            database,
            sql: "SELECT updated_at FROM libraries WHERE id = ?",
            arguments: [libraryID]
        )
        let searches = try Row.fetchAll(
            database,
            sql: """
            SELECT object_key,
                   COALESCE(
                       json_extract(current_json, '$.data.name'),
                       json_extract(current_json, '$.name'),
                       object_key
                   ) AS name
            FROM zotero_objects
            WHERE library_id = ? AND object_kind = 'search' AND is_deleted = 0
            ORDER BY name COLLATE NOCASE, object_key
            """,
            arguments: [libraryID]
        ).map { row in
            ZoteroSavedSearchSummary(key: row["object_key"], name: row["name"])
        }
        let deletedItemCount = try Int.fetchOne(
            database,
            sql: """
            SELECT COUNT(*) FROM zotero_objects
            WHERE library_id = ? AND object_kind = 'item' AND is_deleted = 1
            """,
            arguments: [libraryID]
        ) ?? 0
        return ZoteroLibraryNavigationSnapshot(
            savedSearches: searches,
            deletedItemCount: deletedItemCount
        )
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
