@testable import CitrationCore
import Foundation
import Testing

// MARK: - LargeLibraryPerformanceTests

@Suite("Large library performance")
struct LargeLibraryPerformanceTests {
    // MARK: Internal

    @Test("ten thousand captured-shape items remain responsive in real SQLite")
    func tenThousandItemsRemainResponsive() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-large-library-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try CitrationDatabase(at: directory.appending(path: "library.sqlite"))
        let libraryID = try database.upsertLibrary(
            identity: .init(type: "user", remoteID: 10000),
            name: "Large Library Acceptance"
        )
        let objects = try makeCapturedShapeItems(count: 10000)
        let store = try CitrationLibraryStore(
            database: database,
            attachmentsDirectory: directory.appending(path: "attachments", directoryHint: .isDirectory),
            libraryIdentity: .init(type: "user", remoteID: 10000),
            libraryName: "Large Library Acceptance"
        )

        let clock = ContinuousClock()
        let ingestion = try clock.measure {
            try database.storeRemoteItems(objects, libraryID: libraryID)
            try database.ensureAppIdentities(collections: [], items: objects, libraryID: libraryID)
        }
        let tableReadStart = clock.now
        let tableItems = await store.listLibraryItems()
        let tableRead = tableReadStart.duration(to: clock.now)
        let searchStart = clock.now
        let searchKeys = try database.searchLibraryItemKeys(
            libraryID: libraryID,
            query: "unique-performance-marker-7777"
        )
        let search = searchStart.duration(to: clock.now)

        #expect(tableItems.count == objects.count)
        #expect(searchKeys.count == 1)
        #expect(ingestion < .seconds(60))
        #expect(tableRead < .seconds(5))
        #expect(search < .seconds(2))
        #expect(try database.integrityCheck() == "ok")
    }

    // MARK: Private

    private func makeCapturedShapeItems(count: Int) throws -> [ZoteroRawObject] {
        let fixtureURL = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/Zotero/items.json")
        )
        let captured = try JSONDecoder().decode([ZoteroRawObject].self, from: Data(contentsOf: fixtureURL))
        let template = try #require(captured.first { object in
            guard let itemType = object.itemType else {
                return false
            }
            return !["annotation", "attachment", "note"].contains(itemType)
        })

        return try (0 ..< count).map { index in
            let key = ZoteroObjectKey.deterministic(namespace: "large-library", value: String(index))
            var envelope = try #require(template.rawValue.objectValue)
            var data = try #require(envelope["data"]?.objectValue)
            data["key"] = .string(key)
            data["version"] = .integer(1)
            data["title"] = .string(
                index == 7777
                    ? "Captured Work unique-performance-marker-7777"
                    : "Captured Work \(index)"
            )
            data["collections"] = .array([])
            envelope["key"] = .string(key)
            envelope["version"] = .integer(1)
            envelope["data"] = .object(data)
            return try ZoteroRawObject(rawValue: .object(envelope))
        }
    }
}
