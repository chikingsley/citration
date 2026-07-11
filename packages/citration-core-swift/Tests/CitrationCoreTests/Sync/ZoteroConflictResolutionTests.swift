@testable import CitrationCore
import Foundation
import Testing

// MARK: - ZoteroConflictResolutionTests

@Suite("Zotero conflict resolution")
struct ZoteroConflictResolutionTests {
    // MARK: Internal

    @Test("Keeping remote resolves the failure and restores a synced pristine object")
    func keepRemote() throws {
        try withConflict { database, libraryID, key, _, remote in
            try database.resolveConflict(kind: .item, key: key, resolution: .keepRemote, libraryID: libraryID)

            let resolved = try #require(
                try database.fetchObject(libraryID: libraryID, kind: .item, key: key)
            )
            #expect(resolved.syncState == .synced)
            #expect(resolved.current == remote.rawValue)
            #expect(resolved.pristine == remote.rawValue)
            #expect(try database.unresolvedSyncFailureCount(libraryID: libraryID) == 0)
        }
    }

    @Test("Keeping local rebases it onto the remote version for a safe retry")
    func keepLocal() throws {
        try withConflict { database, libraryID, key, local, remote in
            try database.resolveConflict(kind: .item, key: key, resolution: .keepLocal, libraryID: libraryID)

            let resolved = try #require(
                try database.fetchObject(libraryID: libraryID, kind: .item, key: key)
            )
            #expect(resolved.syncState == .dirty)
            #expect(resolved.version == remote.version)
            #expect(resolved.pristine == remote.rawValue)
            #expect(resolved.current.objectValue?["data"]?.objectValue?["title"] == local.data["title"])
            #expect(try database.pendingUploads(kind: .item, libraryID: libraryID).map(\.key) == [key])
            #expect(try database.unresolvedSyncFailureCount(libraryID: libraryID) == 0)
        }
    }

    @Test("Choosing deletion resolves the conflict into the durable deletion queue")
    func chooseDeletion() throws {
        try withConflict { database, libraryID, key, _, _ in
            try database.resolveConflict(kind: .item, key: key, resolution: .delete, libraryID: libraryID)

            let resolved = try #require(
                try database.fetchObject(libraryID: libraryID, kind: .item, key: key)
            )
            #expect(resolved.syncState == .deleted)
            #expect(resolved.isDeleted)
            #expect(try database.pendingDeletions(kind: .item, libraryID: libraryID) == [key])
            #expect(try database.fetchProjectedItem(libraryID: libraryID, key: key) == nil)
        }
    }

    // MARK: Private

    private func withConflict(
        _ body: (
            CitrationDatabase,
            Int64,
            String,
            ZoteroRawObject,
            ZoteroRawObject
        ) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "citration-conflict-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try CitrationDatabase(at: root.appending(path: "library.sqlite"))
        let libraryID = try database.upsertLibrary(
            identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
            currentVersion: 1291
        )
        let original = try #require(capturedObjects(filename: "items.json").first {
            $0.itemType == "journalArticle"
        })
        let key = try #require(original.key)
        try database.storeRemoteCollections(capturedObjects(filename: "collections.json"), libraryID: libraryID)
        try database.storeRemoteItems([original], libraryID: libraryID)
        let local = try replacingTitle("Local title", in: original)
        let remote = try replacingTitle("Remote title", in: original, version: 1300)
        try database.storeLocalItems([local], libraryID: libraryID)
        try database.integrateRemoteItems([remote], libraryID: libraryID)
        try body(database, libraryID, key, local, remote)
    }

    private func replacingTitle(
        _ title: String,
        in object: ZoteroRawObject,
        version: Int64? = nil
    ) throws -> ZoteroRawObject {
        var envelope = try #require(object.rawValue.objectValue)
        var data = try #require(envelope["data"]?.objectValue)
        data["title"] = .string(title)
        if let version {
            envelope["version"] = .integer(version)
            data["version"] = .integer(version)
        }
        envelope["data"] = .object(data)
        return try ZoteroRawObject(rawValue: .object(envelope))
    }

    private func capturedObjects(filename: String) throws -> [ZoteroRawObject] {
        let fixtureURL = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/Zotero/\(filename)")
        )
        return try JSONDecoder().decode([ZoteroRawObject].self, from: Data(contentsOf: fixtureURL))
    }
}
