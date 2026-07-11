@testable import Citration
import CitrationCore
import Foundation
import Testing

@MainActor
@Suite("Synchronization recovery")
struct SyncRecoveryTests {
    // MARK: Internal

    @Test("selected synchronized attachments expose missing download state")
    func selectedRemoteAttachmentExposesDownloadState() async throws {
        let item = BCItem(title: "Remote Parent")
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)
        let parentKey = try #require(model.selectedLibraryItem?.identity.objectKey)
        let libraryID = try #require(model.selectedLibraryItem?.identity.libraryID)
        let attachment = try remoteAttachment(parentKey: parentKey)

        try model.database.storeRemoteItems([attachment], libraryID: libraryID)
        try model.database.ensureAppIdentities(collections: [], items: [attachment], libraryID: libraryID)
        model.refreshSelectedAttachmentCacheRecords()

        #expect(model.importer.selectedItemAttachments.isEmpty)
        #expect(model.selectedAttachmentCacheRecords.map(\.itemKey) == ["REMOTE01"])
        #expect(model.selectedAttachmentCacheRecords.first?.cacheState == .notDownloaded)
        #expect(model.selectedAttachmentCacheRecords.first?.filename == "remote-paper.pdf")
    }

    // MARK: Private

    private func remoteAttachment(parentKey: String) throws -> ZoteroRawObject {
        try ZoteroRawObject(rawValue: .object([
            "key": .string("REMOTE01"),
            "version": .integer(9),
            "data": .object([
                "key": .string("REMOTE01"),
                "version": .integer(9),
                "itemType": .string("attachment"),
                "parentItem": .string(parentKey),
                "linkMode": .string("imported_file"),
                "contentType": .string("application/pdf"),
                "filename": .string("remote-paper.pdf"),
                "tags": .array([]),
                "collections": .array([]),
            ]),
        ]))
    }
}
