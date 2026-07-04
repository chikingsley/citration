import Testing
import Foundation
@testable import Citration
import CitrationCore

@Suite("LocalReaderProgressStore")
struct ReaderProgressStoreTests {
    @Test("stores and loads progress by attachment key")
    func storesAndLoadsProgressByAttachmentKey() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let storeURL = directory.appendingPathComponent("reader-progress.json")
        let store = try LocalReaderProgressStore(storeURL: storeURL)
        let progress = try await store.upsert(
            ReaderProgress(
                itemID: UUID(),
                attachmentKey: "item/paper.pdf",
                location: .page(12),
                fractionComplete: 1.2
            )
        )

        let reloadedStore = try LocalReaderProgressStore(storeURL: storeURL)
        let reloaded = try await reloadedStore.progress(for: "item/paper.pdf")

        #expect(reloaded == progress)
        #expect(reloaded?.fractionComplete == 1)
    }

    @Test("upsert replaces existing attachment progress")
    func upsertReplacesExistingAttachmentProgress() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalReaderProgressStore(storeURL: directory.appendingPathComponent("reader-progress.json"))
        let itemID = UUID()
        _ = try await store.upsert(
            ReaderProgress(itemID: itemID, attachmentKey: "item/paper.pdf", location: .page(1))
        )

        let updated = try await store.upsert(
            ReaderProgress(
                itemID: itemID,
                attachmentKey: "item/paper.pdf",
                location: .page(4),
                fractionComplete: 0.5
            )
        )
        let progress = try await store.listProgress(itemID: itemID)

        #expect(progress == [updated])
        #expect(progress.first?.location == .page(4))
    }

    @Test("removeProgress deletes progress for item IDs")
    func removeProgressDeletesProgressForItemIDs() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalReaderProgressStore(storeURL: directory.appendingPathComponent("reader-progress.json"))
        let removedID = UUID()
        let keptID = UUID()
        _ = try await store.upsert(
            ReaderProgress(itemID: removedID, attachmentKey: "removed/paper.pdf", location: .page(2))
        )
        _ = try await store.upsert(
            ReaderProgress(itemID: keptID, attachmentKey: "kept/paper.pdf", location: .page(3))
        )

        try await store.removeProgress(itemIDs: [removedID])

        #expect(try await store.progress(for: "removed/paper.pdf") == nil)
        #expect(try await store.progress(for: "kept/paper.pdf")?.location == .page(3))
    }
}

private extension ReaderProgressStoreTests {
    func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-reader-progress-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
