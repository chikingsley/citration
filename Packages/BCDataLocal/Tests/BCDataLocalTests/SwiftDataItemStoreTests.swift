import Testing
import Foundation
@testable import BCDataLocal
import BCDomain
import BCCommon

@Suite("SwiftDataItemStore")
struct SwiftDataItemStoreTests {
    @Test("upsert persists items across store reinitialization")
    func upsertPersistsAcrossStoreReinitialization() async throws {
        let storeURL = try makeStoreURL()
        defer { cleanupStoreArtifacts(for: storeURL) }

        let itemID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let inputItem = BCItem(
            id: itemID,
            title: "Persistent Item",
            identifiers: [Identifier(type: .doi, value: "10.1000/persist")],
            itemType: .article,
            creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
            publicationYear: 1843,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let firstStore = try SwiftDataItemStore(storeURL: storeURL)
        await firstStore.upsert(inputItem)

        let secondStore = try SwiftDataItemStore(storeURL: storeURL)
        let fetchedItems = await secondStore.listItems()

        #expect(fetchedItems.count == 1)
        let fetched = try #require(fetchedItems.first)
        #expect(fetched.id == inputItem.id)
        #expect(fetched.title == inputItem.title)
        #expect(fetched.identifiers == inputItem.identifiers)
        #expect(fetched.itemType == inputItem.itemType)
        #expect(fetched.creators == inputItem.creators)
        #expect(fetched.publicationYear == inputItem.publicationYear)
        #expect(fetched.createdAt == inputItem.createdAt)
    }

    @Test("upsert preserves createdAt for existing records")
    func upsertPreservesCreatedAt() async throws {
        let storeURL = try makeStoreURL()
        defer { cleanupStoreArtifacts(for: storeURL) }

        let itemID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_234)
        let store = try SwiftDataItemStore(storeURL: storeURL)

        let firstVersion = BCItem(
            id: itemID,
            title: "Version One",
            identifiers: [Identifier(type: .doi, value: "10.1000/v1")],
            itemType: .article,
            creators: [Creator(givenName: "Grace", familyName: "Hopper")],
            publicationYear: 1952,
            createdAt: createdAt,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        await store.upsert(firstVersion)
        try await Task.sleep(nanoseconds: 5_000_000)

        var secondVersion = firstVersion
        secondVersion.title = "Version Two"
        secondVersion.publicationYear = 1953
        secondVersion.updatedAt = Date(timeIntervalSince1970: 2_100)

        await store.upsert(secondVersion)

        let fetched = try #require(await store.listItems().first)
        #expect(fetched.title == "Version Two")
        #expect(fetched.publicationYear == 1953)
        #expect(fetched.createdAt == createdAt)
        #expect(fetched.updatedAt > firstVersion.updatedAt)
    }

    @Test("removeItem deletes persisted record")
    func removeItemDeletesPersistedRecord() async throws {
        let storeURL = try makeStoreURL()
        defer { cleanupStoreArtifacts(for: storeURL) }

        let store = try SwiftDataItemStore(storeURL: storeURL)
        let removable = BCItem(title: "Will be removed")

        await store.upsert(removable)
        #expect(await store.listItems().count == 1)

        await store.removeItem(id: removable.id)
        #expect(await store.listItems().isEmpty)

        let reopenedStore = try SwiftDataItemStore(storeURL: storeURL)
        #expect(await reopenedStore.listItems().isEmpty)
    }
}

private extension SwiftDataItemStoreTests {
    func makeStoreURL() throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("better-cite-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        return temporaryDirectory.appendingPathComponent("items.store")
    }

    func cleanupStoreArtifacts(for storeURL: URL) {
        let basePath = storeURL.path
        let fileManager = FileManager.default

        let candidates = [
            storeURL,
            URL(fileURLWithPath: basePath + "-wal"),
            URL(fileURLWithPath: basePath + "-shm")
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            try? fileManager.removeItem(at: candidate)
        }

        try? fileManager.removeItem(at: storeURL.deletingLastPathComponent())
    }
}
