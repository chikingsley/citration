@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - NoteStoreTests

@Suite("LocalNoteStore")
struct NoteStoreTests {
    @Test("stores and lists notes on disk")
    func storesAndListsNotesOnDisk() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let storeURL = directory.appendingPathComponent("notes.json")
        let store = try LocalNoteStore(storeURL: storeURL)
        let itemID = UUID()
        let saved = try await store.upsert(
            LibraryNote(itemID: itemID, text: "  Read the method section  ")
        )

        let reloadedStore = try LocalNoteStore(storeURL: storeURL)
        let notes = try await reloadedStore.listNotes(itemID: itemID)

        #expect(notes == [saved])
        #expect(notes.first?.text == "Read the method section")
    }

    @Test("upsert preserves createdAt and updates text")
    func upsertPreservesCreatedAtAndUpdatesText() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalNoteStore(storeURL: directory.appendingPathComponent("notes.json"))
        let createdAt = Date(timeIntervalSince1970: 1)
        let original = try await store.upsert(
            LibraryNote(
                itemID: UUID(),
                text: "First",
                createdAt: createdAt,
                updatedAt: createdAt
            )
        )

        var edited = original
        edited.text = "  Edited  "
        let updated = try await store.upsert(edited)

        #expect(updated.createdAt == original.createdAt)
        #expect(updated.updatedAt >= original.updatedAt)
        #expect(updated.text == "Edited")
    }

    @Test("removeNotes deletes all notes for item IDs")
    func removeNotesDeletesAllNotesForItemIDs() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalNoteStore(storeURL: directory.appendingPathComponent("notes.json"))
        let removedID = UUID()
        let keptID = UUID()
        _ = try await store.upsert(LibraryNote(itemID: removedID, text: "Remove"))
        _ = try await store.upsert(LibraryNote(itemID: keptID, text: "Keep"))

        try await store.removeNotes(itemIDs: [removedID])

        #expect(try await store.listNotes(itemID: removedID).isEmpty)
        #expect(try await store.listNotes(itemID: keptID).count == 1)
    }
}

private extension NoteStoreTests {
    func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-note-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
