import Foundation
import Testing
@testable import Citration
import CitrationCore

struct AnnotationStoreTests {
    @Test("stores and lists annotations on disk")
    func storesAndListsAnnotationsOnDisk() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let storeURL = directory.appendingPathComponent("annotations.json")
        let store = try LocalAnnotationStore(storeURL: storeURL)
        let itemID = UUID()

        let saved = try await store.upsert(
            LibraryAnnotation(
                itemID: itemID,
                attachmentKey: "item/paper.pdf",
                location: .page(3),
                note: "Read again"
            )
        )

        let reloadedStore = try LocalAnnotationStore(storeURL: storeURL)
        let annotations = try await reloadedStore.listAnnotations(
            itemID: itemID,
            attachmentKey: "item/paper.pdf"
        )

        #expect(annotations == [saved])
    }

    @Test("upsert preserves createdAt and updates note")
    func upsertPreservesCreatedAtAndUpdatesNote() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalAnnotationStore(storeURL: directory.appendingPathComponent("annotations.json"))
        let itemID = UUID()

        let saved = try await store.upsert(
            LibraryAnnotation(
                itemID: itemID,
                attachmentKey: "item/paper.pdf",
                note: "First note",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        )

        var edited = saved
        edited.note = "Edited note"
        let updated = try await store.upsert(edited)

        #expect(updated.createdAt == saved.createdAt)
        #expect(updated.note == "Edited note")
        #expect(updated.updatedAt >= saved.updatedAt)
    }

    @Test("remove deletes annotation")
    func removeDeletesAnnotation() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let store = try LocalAnnotationStore(storeURL: directory.appendingPathComponent("annotations.json"))
        let itemID = UUID()

        let saved = try await store.upsert(
            LibraryAnnotation(itemID: itemID, attachmentKey: "item/paper.pdf", note: "Delete me")
        )
        try await store.remove(id: saved.id)

        let annotations = try await store.listAnnotations(itemID: itemID)
        #expect(annotations.isEmpty)
    }

    private func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-annotation-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
