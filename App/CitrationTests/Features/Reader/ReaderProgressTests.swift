@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - ReaderProgressTests

@Suite("Reader Progress")
@MainActor
struct ReaderProgressTests {
    @Test("openReader loads saved progress")
    func openReaderLoadsSavedProgress() async throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let item = BCItem(title: "Paper")
        let attachmentStore = try LocalAttachmentStore(
            baseDirectory: tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        )
        let sourceFile = try makeFile(named: "paper.pdf", contents: Data("dummy".utf8), in: tempDirectory)
        let attachment = try await attachmentStore.importFile(from: sourceFile, for: item)
        let progressStore = try makeReaderProgressStore()
        _ = try await progressStore.upsert(
            ReaderProgress(
                itemID: item.id,
                attachmentKey: attachment.objectKey,
                location: .page(8),
                fractionComplete: 0.4
            )
        )
        let model = makeModel(
            initialItems: [item],
            attachmentStore: attachmentStore,
            readerProgressStore: progressStore
        )
        await model.refreshItems()

        model.openReader(for: attachment)
        try await waitUntil { model.activeReaderProgress?.location == .page(8) }

        #expect(model.activeReaderAttachment == attachment)
        #expect(model.activeReaderProgress?.fractionComplete == 0.4)
    }

    @Test("updateReaderProgress persists active attachment progress")
    func updateReaderProgressPersistsActiveAttachmentProgress() async throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let item = BCItem(title: "Paper")
        let attachmentStore = try LocalAttachmentStore(
            baseDirectory: tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        )
        let sourceFile = try makeFile(named: "paper.pdf", contents: Data("dummy".utf8), in: tempDirectory)
        let attachment = try await attachmentStore.importFile(from: sourceFile, for: item)
        let progressStore = try makeReaderProgressStore()
        let model = makeModel(
            initialItems: [item],
            attachmentStore: attachmentStore,
            readerProgressStore: progressStore
        )
        await model.refreshItems()
        model.openReader(for: attachment)

        model.updateReaderProgress(
            ReaderProgress(
                itemID: item.id,
                attachmentKey: attachment.objectKey,
                location: .page(3),
                fractionComplete: 0.25
            )
        )
        try await waitUntil { model.activeReaderProgress?.location == .page(3) }
        let persisted = try await progressStore.progress(for: attachment.objectKey)

        #expect(persisted?.location == .page(3))
        #expect(persisted?.fractionComplete == 0.25)
    }

    @Test("removeSelectedItem removes reader progress")
    func removeSelectedItemRemovesReaderProgress() async throws {
        let item = BCItem(title: "Paper")
        let attachment = makeAttachment(itemID: item.id, fileName: "paper.pdf")
        let progressStore = try makeReaderProgressStore()
        _ = try await progressStore.upsert(
            ReaderProgress(
                itemID: item.id,
                attachmentKey: attachment.objectKey,
                location: .page(4),
                fractionComplete: 0.5
            )
        )
        let model = makeModel(initialItems: [item], readerProgressStore: progressStore)
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.removeSelectedItem()
        try await waitUntil { model.items.isEmpty }

        #expect(try await progressStore.progress(for: attachment.objectKey) == nil)
    }
}

private extension ReaderProgressTests {
    func makeModel(
        initialItems: [BCItem],
        attachmentStore: LocalAttachmentStore? = nil,
        readerProgressStore: LocalReaderProgressStore
    ) -> AppModel {
        AppModel(
            store: InMemoryItemStore(initialItems: initialItems),
            metadataRegistry: MetadataProviderRegistry(providers: [NoopMetadataProvider()]),
            citationFormatter: StubCitationFormatter(),
            storageConnectors: [],
            pdfDOIExtractor: NullPDFDOIExtractor(),
            attachmentStore: attachmentStore,
            annotationStore: makeAnnotationStore(),
            collectionStore: makeCollectionStore(),
            noteStore: makeNoteStore(),
            relationshipStore: makeRelationshipStore(),
            readerProgressStore: readerProgressStore
        )
    }

    func waitUntil(
        timeout: TimeInterval = 2.0,
        pollInterval: UInt64 = 10_000_000,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        Issue.record("Timed out waiting for condition")
    }

    func makeAttachment(itemID: UUID, fileName: String) -> LocalAttachment {
        LocalAttachment(
            itemID: itemID,
            fileName: fileName,
            objectKey: "\(itemID.uuidString)/\(fileName)",
            localURL: URL(fileURLWithPath: "/tmp/\(fileName)"),
            contentType: "application/pdf",
            size: 128,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-reader-progress-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeFile(named fileName: String, contents: Data, in directory: URL) throws -> URL {
        let fileURL = directory.appendingPathComponent(fileName)
        try contents.write(to: fileURL)
        return fileURL
    }

    func makeAnnotationStore() -> LocalAnnotationStore? {
        try? LocalAnnotationStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-reader-progress-annotations")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeCollectionStore() -> LocalCollectionStore? {
        try? LocalCollectionStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-reader-progress-collections")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeNoteStore() -> LocalNoteStore? {
        try? LocalNoteStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-reader-progress-notes")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeRelationshipStore() -> LocalRelationshipStore? {
        try? LocalRelationshipStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-reader-progress-relationships")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeReaderProgressStore() throws -> LocalReaderProgressStore {
        try LocalReaderProgressStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-reader-progress-tests")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }
}
