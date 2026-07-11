import CitrationCore
@testable import CitrationPad
import Foundation
import Testing

@Suite("iPad library model")
@MainActor
struct IPadLibraryModelTests {
    @Test("opens and restores a real SQLite library scene")
    func realLibraryAndCollectionFiltering() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-ipad-tests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try CitrationDatabase(at: directory.appending(path: "library.sqlite"))
        let store = try CitrationLibraryStore(
            database: database,
            attachmentsDirectory: directory.appending(path: "attachments", directoryHint: .isDirectory),
            initialItems: [BCItem(title: "Portable Research")]
        )
        let collection = try await store.createCollection(name: "Reading")
        let item = try #require(await store.listLibraryItems().first)
        _ = try await store.addItem(item.identity.appUUID, to: collection.id)
        _ = try await store.upsert(LibraryNote(itemID: item.identity.appUUID, text: "<p>Portable note</p>"))
        let documentURL = directory.appending(path: "portable.txt")
        try Data("Offline reader evidence".utf8).write(to: documentURL)
        let attachment = try await store.importFile(from: documentURL, for: item.bibliographic)
        let model = IPadLibraryModel(
            database: database,
            store: store,
            connectionManager: ZoteroConnectionManager(
                database: database,
                credentialStore: FileZoteroCredentialStore(
                    fileURL: directory.appending(path: "zotero-device-api-key")
                ),
                attachmentsDirectory: directory.appending(path: "attachments", directoryHint: .isDirectory)
            )
        )

        await model.reloadAll()
        await model.restoreScene(
            sourceToken: "collection:\(collection.id.uuidString)",
            itemKey: item.identity.objectKey,
            attachmentKey: attachment.objectKey
        )

        #expect(model.visibleItems.map(\.title) == ["Portable Research"])
        #expect(model.selectedItemIdentity == item.identity)
        #expect(model.selectedNotes.map(\.html) == ["<p>Portable note</p>"])
        #expect(model.openDocument?.record.itemKey == attachment.objectKey)
        #expect(model.sceneToken(for: model.selectedSource) == "collection:\(collection.id.uuidString)")
        #expect(try database.integrityCheck() == "ok")
    }
}
