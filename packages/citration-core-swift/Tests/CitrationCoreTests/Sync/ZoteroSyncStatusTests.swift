@testable import CitrationCore
import Foundation
import Testing

@Suite("Zotero synchronization status")
struct ZoteroSyncStatusTests {
    // MARK: Internal

    @Test("Status summarizes durable object and attachment work")
    func synchronizationStatusSnapshot() throws {
        try withTemporaryDatabase { database in
            let libraryID = try database.upsertLibrary(
                identity: ZoteroLibraryIdentity(type: "user", remoteID: 1),
                currentVersion: 1291
            )
            let items = try capturedItems()
            let edited = try #require(items.first { $0.itemType == "journalArticle" })
            let deleted = try #require(items.first { item in
                item.key != edited.key && !["annotation", "attachment", "note"].contains(item.itemType)
            })
            let attachment = try #require(items.first { $0.itemType == "attachment" })
            try database.storeRemoteCollections(capturedObjects(filename: "collections.json"), libraryID: libraryID)
            try database.storeRemoteItems([edited, deleted, attachment], libraryID: libraryID)
            try database.storeLocalItems(
                [replacingTitle(in: edited, with: "Locally edited fixture")],
                libraryID: libraryID
            )
            let editedKey = try #require(edited.key)
            let fetched = try database.fetchObject(libraryID: libraryID, kind: .item, key: editedKey)
            let stored = try #require(fetched)
            try database.recordWriteTransportFailure(
                objects: [stored],
                operation: "upload",
                message: "fixture transport failure",
                libraryID: libraryID
            )
            try database.markLocalDeletion(
                kind: .item,
                key: #require(deleted.key),
                libraryID: libraryID
            )
            try database.markAttachmentTransferFailed(
                libraryID: libraryID,
                itemKey: #require(attachment.key),
                operation: "attachment-download",
                message: "fixture attachment failure"
            )

            let status = try database.syncStatusSnapshot(libraryID: libraryID)

            #expect(status.currentVersion == 1291)
            #expect(status.pendingUploadCount == 1)
            #expect(status.pendingDeletionCount == 1)
            #expect(status.failedAttachmentCount == 1)
            #expect(status.failures.count == 2)
            #expect(Set(status.failures.map(\.operation)) == ["upload", "attachment-download"])
        }
    }

    // MARK: Private

    private func capturedItems() throws -> [ZoteroRawObject] {
        try capturedObjects(filename: "items.json")
    }

    private func capturedObjects(filename: String) throws -> [ZoteroRawObject] {
        let fixtureURL = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/Zotero/\(filename)")
        )
        return try JSONDecoder().decode([ZoteroRawObject].self, from: Data(contentsOf: fixtureURL))
    }

    private func replacingTitle(in object: ZoteroRawObject, with title: String) throws -> ZoteroRawObject {
        var envelope = try #require(object.rawValue.objectValue)
        var data = try #require(envelope["data"]?.objectValue)
        data["title"] = .string(title)
        envelope["data"] = .object(data)
        return try ZoteroRawObject(rawValue: .object(envelope))
    }

    private func withTemporaryDatabase(_ body: (CitrationDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-sync-status-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(CitrationDatabase(at: directory.appending(path: "library.sqlite")))
    }
}
