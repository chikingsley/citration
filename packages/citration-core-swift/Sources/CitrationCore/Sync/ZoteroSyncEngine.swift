import Foundation

// MARK: - ZoteroPullReport

public struct ZoteroPullReport: Equatable, Sendable {
    public let userID: Int64
    public let previousVersion: Int64
    public let currentVersion: Int64
    public let collectionCount: Int
    public let itemCount: Int
    public let searchCount: Int
    public let settingCount: Int
    public let fullTextCount: Int
    public let deletionCount: Int
    public let groupCount: Int
}

// MARK: - ZoteroSyncError

public enum ZoteroSyncError: Error, Equatable, Sendable {
    case remoteLibraryKeptChanging(attempts: Int)
}

// MARK: - ZoteroSyncEngine

public struct ZoteroSyncEngine: Sendable {
    // MARK: Lifecycle

    public init(database: CitrationDatabase, client: ZoteroAPIClient) {
        self.database = database
        self.client = client
    }

    // MARK: Public

    public func pullReadOnly(maxConsistencyAttempts: Int = 3) async throws -> ZoteroPullReport {
        let keyInfo = try await client.keyInfo()
        let identity = ZoteroLibraryIdentity(type: "user", remoteID: keyInfo.userID)
        let previousVersion = try database.libraryVersion(identity: identity)
        let libraryID = try database.upsertLibrary(
            identity: identity,
            name: keyInfo.displayName,
            currentVersion: previousVersion
        )

        for _ in 0 ..< maxConsistencyAttempts {
            let data = try await fetchChanges(userID: keyInfo.userID, since: previousVersion)
            try persist(data, libraryID: libraryID)
            let stability = try await client.versions(
                path: "users/\(keyInfo.userID)/items",
                since: data.version,
                extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
            )
            let stableVersion = stability.libraryVersion ?? data.version
            guard stability.value.isEmpty, stableVersion <= data.version else {
                continue
            }
            try database.setLibraryVersion(data.version, libraryID: libraryID)
            return data.report(userID: keyInfo.userID, previousVersion: previousVersion)
        }
        throw ZoteroSyncError.remoteLibraryKeptChanging(attempts: maxConsistencyAttempts)
    }

    // MARK: Internal

    let database: CitrationDatabase
    let client: ZoteroAPIClient

    // MARK: Private

    private static func maximumVersion(_ values: [Int64?], fallback: Int64) -> Int64 {
        values.compactMap(\.self).max() ?? fallback
    }

    private func fetchChanges(userID: Int64, since: Int64) async throws -> ZoteroPullData {
        async let collectionVersions = client.versions(path: "users/\(userID)/collections", since: since)
        async let itemVersions = client.versions(
            path: "users/\(userID)/items",
            since: since,
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        async let searchVersions = client.versions(path: "users/\(userID)/searches", since: since)
        async let settings = client.settings(userID: userID, since: since)
        async let deletions = client.deleted(userID: userID, since: since)
        async let fullTextVersions = client.fullTextVersions(userID: userID, since: since)
        async let groups = client.groups(userID: userID)

        let (collectionMap, itemMap, searchMap) = try await (
            collectionVersions,
            itemVersions,
            searchVersions
        )
        async let collections = client.objects(
            path: "users/\(userID)/collections",
            keyParameter: "collectionKey",
            keys: Array(collectionMap.value.keys)
        )
        async let items = client.objects(
            path: "users/\(userID)/items",
            keyParameter: "itemKey",
            keys: Array(itemMap.value.keys),
            extraQuery: [URLQueryItem(name: "includeTrashed", value: "1")]
        )
        async let searches = client.objects(
            path: "users/\(userID)/searches",
            keyParameter: "searchKey",
            keys: Array(searchMap.value.keys)
        )
        let (settingData, deletionData, fullTextMap, groupData) = try await (
            settings,
            deletions,
            fullTextVersions,
            groups
        )
        let fullTexts = try await fetchFullTexts(userID: userID, versions: fullTextMap.value)
        return try await ZoteroPullData(
            collections: collections.value,
            items: items.value,
            searches: searches.value,
            settings: settingData.value,
            deletions: deletionData.value,
            fullTexts: fullTexts,
            groups: groupData.value,
            version: Self.maximumVersion([
                collectionMap.libraryVersion,
                itemMap.libraryVersion,
                searchMap.libraryVersion,
                settingData.libraryVersion,
                deletionData.libraryVersion,
                fullTextMap.libraryVersion,
            ], fallback: since)
        )
    }

    private func fetchFullTexts(
        userID: Int64,
        versions: [String: Int64]
    ) async throws -> [ZoteroPulledFullText] {
        let entries = Array(versions)
        var iterator = entries.makeIterator()
        return try await withThrowingTaskGroup(of: ZoteroPulledFullText.self) { group in
            for _ in 0 ..< min(6, entries.count) {
                if let entry = iterator.next() {
                    group.addTask { try await fetchFullText(userID: userID, entry: entry) }
                }
            }
            var results = [ZoteroPulledFullText]()
            while let result = try await group.next() {
                results.append(result)
                if let entry = iterator.next() {
                    group.addTask { try await fetchFullText(userID: userID, entry: entry) }
                }
            }
            return results
        }
    }

    private func fetchFullText(
        userID: Int64,
        entry: (key: String, value: Int64)
    ) async throws -> ZoteroPulledFullText {
        let response = try await client.fullText(userID: userID, itemKey: entry.key)
        return ZoteroPulledFullText(
            itemKey: entry.key,
            version: response.libraryVersion ?? entry.value,
            value: response.value
        )
    }

    private func persist(_ data: ZoteroPullData, libraryID: Int64) throws {
        try database.integrateRemoteCollections(data.collections, libraryID: libraryID)
        try database.integrateRemoteItems(data.items, libraryID: libraryID)
        try database.ensureAppIdentities(
            collections: data.collections,
            items: data.items,
            libraryID: libraryID
        )
        try database.storeRemoteSearches(data.searches, libraryID: libraryID)
        try database.storeRemoteSettings(data.settings, libraryID: libraryID)
        try database.storeRemoteGroups(data.groups, libraryID: libraryID)
        for fullText in data.fullTexts {
            try database.storeRemoteFullText(
                itemKey: fullText.itemKey,
                version: fullText.version,
                response: fullText.value,
                libraryID: libraryID
            )
        }
        try database.applyRemoteDeletions(
            data.deletions,
            version: data.version,
            libraryID: libraryID
        )
    }
}

// MARK: - ZoteroPullData

private struct ZoteroPullData: Sendable {
    let collections: [ZoteroRawObject]
    let items: [ZoteroRawObject]
    let searches: [ZoteroRawObject]
    let settings: JSONValue
    let deletions: ZoteroDeletedObjects
    let fullTexts: [ZoteroPulledFullText]
    let groups: [JSONValue]
    let version: Int64

    func report(userID: Int64, previousVersion: Int64) -> ZoteroPullReport {
        ZoteroPullReport(
            userID: userID,
            previousVersion: previousVersion,
            currentVersion: version,
            collectionCount: collections.count,
            itemCount: items.count,
            searchCount: searches.count,
            settingCount: settings.objectValue?.count ?? 0,
            fullTextCount: fullTexts.count,
            deletionCount: deletions.collections.count + deletions.items.count
                + deletions.searches.count + deletions.settings.count,
            groupCount: groups.count
        )
    }
}

// MARK: - ZoteroPulledFullText

private struct ZoteroPulledFullText: Sendable {
    let itemKey: String
    let version: Int64
    let value: JSONValue
}
