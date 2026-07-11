@testable import CitrationCore
import Foundation
import Testing

// MARK: - ZoteroWriteQueueTests

@Suite("Zotero write queue")
struct ZoteroWriteQueueTests {
    // MARK: Internal

    @Test("A successful version-zero write becomes a synced pristine object")
    func successfulCreateLeavesNoDirtyState() throws {
        try withTemporaryDatabase { database in
            let libraryID = try database.upsertLibrary(
                identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
                currentVersion: 1291
            )
            let item = BCItem(title: "Disposable write fixture")
            let key = LegacyZoteroObjectFactory.itemKey(for: item.id)
            let local = try LegacyZoteroObjectFactory.itemObject(item, key: key, collectionKeys: [])
            try database.storeLocalItems([local], libraryID: libraryID)
            let pending = try database.pendingUploads(kind: .item, libraryID: libraryID)
            #expect(pending.count == 1)
            #expect(pending[0].version == 0)
            #expect(ZoteroObjectKey.isValid(pending[0].key))
            let remote = try replacingField("title", with: .string(item.title), in: local, version: 1300)

            try database.applyWriteReport(
                ZoteroWriteReport(
                    success: ["0": key],
                    successful: ["0": remote]
                ),
                batch: pending,
                kind: .item,
                libraryVersion: 1300,
                libraryID: libraryID
            )

            let stored = try #require(try database.fetchObject(libraryID: libraryID, kind: .item, key: key))
            #expect(stored.syncState == .synced)
            #expect(stored.version == 1300)
            #expect(stored.current == remote.rawValue)
            #expect(stored.pristine == remote.rawValue)
            #expect(try database.pendingUploads(kind: .item, libraryID: libraryID).isEmpty)
        }
    }

    @Test("Failed writes stay durable and respect their retry time")
    func failedWriteUsesPersistentRetryQueue() throws {
        try withTemporaryDatabase { database in
            let (libraryID, original) = try seedRemoteArticle(in: database)
            let key = try #require(original.key)
            let local = try replacingField("title", with: .string("Retry me"), in: original)
            try database.storeLocalItems([local], libraryID: libraryID)
            let pending = try database.pendingUploads(kind: .item, libraryID: libraryID)

            try database.applyWriteReport(
                ZoteroWriteReport(failed: [
                    "0": ZoteroWriteFailure(key: key, code: 500, message: "Disposable failure")
                ]),
                batch: pending,
                kind: .item,
                libraryVersion: 1291,
                libraryID: libraryID
            )

            let failed = try #require(try database.fetchObject(libraryID: libraryID, kind: .item, key: key))
            #expect(failed.syncState == .failed)
            #expect(try database.pendingUploads(kind: .item, libraryID: libraryID).isEmpty)
            #expect(
                try database.pendingUploads(
                    kind: .item,
                    libraryID: libraryID,
                    now: Date().addingTimeInterval(31)
                ).map(\.key) == [key]
            )
            #expect(try database.unresolvedSyncFailureCount(libraryID: libraryID) == 1)
        }
    }

    // MARK: Private

    private func replacingField(
        _ field: String,
        with value: JSONValue,
        in object: ZoteroRawObject,
        version: Int64? = nil
    ) throws -> ZoteroRawObject {
        var envelope = try #require(object.rawValue.objectValue)
        var data = try #require(envelope["data"]?.objectValue)
        data[field] = value
        if let version {
            data["version"] = .integer(version)
            envelope["version"] = .integer(version)
        }
        envelope["data"] = .object(data)
        return try ZoteroRawObject(rawValue: .object(envelope))
    }

    private func seedRemoteArticle(in database: CitrationDatabase) throws -> (Int64, ZoteroRawObject) {
        let libraryID = try database.upsertLibrary(
            identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
            currentVersion: 1291
        )
        let original = try #require(capturedObjects(filename: "items.json").first {
            $0.itemType == "journalArticle"
        })
        try database.storeRemoteCollections(capturedObjects(filename: "collections.json"), libraryID: libraryID)
        try database.storeRemoteItems([original], libraryID: libraryID)
        return (libraryID, original)
    }

    private func capturedObjects(filename: String) throws -> [ZoteroRawObject] {
        let fixtureURL = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/Zotero/\(filename)")
        )
        return try JSONDecoder().decode([ZoteroRawObject].self, from: Data(contentsOf: fixtureURL))
    }

    private func withTemporaryDatabase(_ body: (CitrationDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-write-queue-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(CitrationDatabase(at: directory.appending(path: "library.sqlite")))
    }
}
