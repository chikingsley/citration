@testable import CitrationCore
import Foundation
import Testing

// MARK: - LocalLibraryPromotionTests

@Suite("Local-only library promotion")
struct LocalLibraryPromotionTests {
    @Test("Connecting promotes all local work transactionally and remains idempotent")
    func promotesLocalWork() async throws {
        let fixture = try PromotionFixture()
        defer { fixture.remove() }
        let localStore = try fixture.makeStore(identity: .init(type: "local", remoteID: 0))
        for item in fixture.items {
            await localStore.upsert(item)
        }
        let collection = try await localStore.createCollection(name: "Local collection", parentID: nil)
        _ = try await localStore.addItem(fixture.items[0].id, to: collection.id)
        let note = try await localStore.upsert(LibraryNote(itemID: fixture.items[0].id, text: "Local note"))
        let attachment = try await localStore.importFile(from: fixture.sourceFile, for: fixture.items[0])
        let progress = try await localStore.upsert(ReaderProgress(
            itemID: fixture.items[0].id,
            attachmentKey: attachment.objectKey,
            location: .page(3),
            fractionComplete: 0.5
        ))
        let relationship = try await localStore.upsert(LibraryRelationship(
            sourceItemID: fixture.items[0].id,
            targetItemID: fixture.items[1].id,
            kind: .cites,
            confidence: 1
        ))
        let sourceKey = try #require(try await localStore.objectKey(for: fixture.items[0].id, kind: .item))
        let targetIdentity = ZoteroLibraryIdentity(type: "user", remoteID: 42)
        try fixture.seedRemoteCollision(identity: targetIdentity, key: sourceKey)

        let report = try fixture.database.promoteLocalLibrary(
            to: targetIdentity,
            targetName: "Remote Library"
        )

        #expect(report.promotedObjectCount == 5)
        #expect(report.remappedKeyCount >= 1)
        let targetStore = try fixture.makeStore(identity: targetIdentity)
        let targetItems = await targetStore.listItems()
        #expect(Set(targetItems.map(\.id)).isSuperset(of: Set(fixture.items.map(\.id))))
        #expect(await localStore.listItems().count == fixture.items.count)
        #expect(try await targetStore.snapshot().collections.contains(collection))
        #expect(try await targetStore.listNotes(itemID: fixture.items[0].id) == [note])
        let promotedAttachments = try await targetStore.listAttachments(for: fixture.items[0].id)
        #expect(promotedAttachments.count == 1)
        #expect(promotedAttachments[0].localURL == attachment.localURL)
        #expect(try await targetStore.progress(for: promotedAttachments[0].objectKey) == progress)
        #expect(try await targetStore.listRelationships().contains(relationship))
        let promotedKey = try #require(try await targetStore.objectKey(for: fixture.items[0].id, kind: .item))
        #expect(promotedKey != sourceKey)
        #expect(ZoteroObjectKey.isValid(promotedKey))

        let second = try fixture.database.promoteLocalLibrary(to: targetIdentity, targetName: "Remote Library")
        #expect(second.promotedObjectCount == 0)
        #expect(second.skippedObjectCount == report.promotedObjectCount)
        #expect(try fixture.database.integrityCheck() == "ok")
    }
}

// MARK: - PromotionFixture

private struct PromotionFixture {
    // MARK: Lifecycle

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "citration-promotion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        database = try CitrationDatabase(at: root.appending(path: "library.sqlite"))
        sourceFile = root.appending(path: "source.pdf")
        try Data("%PDF-1.7\npromotion fixture\n%%EOF\n".utf8).write(to: sourceFile)
    }

    // MARK: Internal

    let root: URL
    let database: CitrationDatabase
    let sourceFile: URL
    let items = [
        BCItem(title: "First local item", itemType: .book),
        BCItem(title: "Second local item", itemType: .article),
    ]

    func makeStore(identity: ZoteroLibraryIdentity) throws -> CitrationLibraryStore {
        try CitrationLibraryStore(
            database: database,
            attachmentsDirectory: root.appending(path: "attachments", directoryHint: .isDirectory),
            libraryIdentity: identity,
            libraryName: identity.type == "local" ? "Local Library" : "Remote Library"
        )
    }

    func seedRemoteCollision(identity: ZoteroLibraryIdentity, key: String) throws {
        let libraryID = try database.upsertLibrary(identity: identity, name: "Remote Library")
        let collision = try LegacyZoteroObjectFactory.itemObject(
            BCItem(title: "Existing remote item", itemType: .book),
            key: key,
            collectionKeys: []
        )
        try database.storeRemoteItems([collision], libraryID: libraryID)
        try database.ensureAppIdentities(collections: [], items: [collision], libraryID: libraryID)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
