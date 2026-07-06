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
        let progressStore = try #require(makeReaderProgressStore())
        _ = try await progressStore.upsert(
            ReaderProgress(
                itemID: item.id,
                attachmentKey: attachment.objectKey,
                location: .page(8),
                fractionComplete: 0.4
            )
        )
        let model = makeAppModel(
            initialItems: [item],
            attachmentStore: attachmentStore,
            readerProgressStore: progressStore
        )
        await model.refreshItems()

        model.reader.open(attachment)
        try await waitUntil { model.reader.progress?.location == .page(8) }

        #expect(model.reader.activeAttachment == attachment)
        #expect(model.reader.progress?.fractionComplete == 0.4)
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
        let progressStore = try #require(makeReaderProgressStore())
        let model = makeAppModel(
            initialItems: [item],
            attachmentStore: attachmentStore,
            readerProgressStore: progressStore
        )
        await model.refreshItems()
        model.reader.open(attachment)

        model.reader.updateProgress(
            ReaderProgress(
                itemID: item.id,
                attachmentKey: attachment.objectKey,
                location: .page(3),
                fractionComplete: 0.25
            )
        )
        try await waitUntil { model.reader.progress?.location == .page(3) }
        let persisted = try await progressStore.progress(for: attachment.objectKey)

        #expect(persisted?.location == .page(3))
        #expect(persisted?.fractionComplete == 0.25)
    }

    @Test("removeSelectedItem removes reader progress")
    func removeSelectedItemRemovesReaderProgress() async throws {
        let item = BCItem(title: "Paper")
        let attachment = makeAttachment(itemID: item.id, fileName: "paper.pdf", contentType: "application/pdf")
        let progressStore = try #require(makeReaderProgressStore())
        _ = try await progressStore.upsert(
            ReaderProgress(
                itemID: item.id,
                attachmentKey: attachment.objectKey,
                location: .page(4),
                fractionComplete: 0.5
            )
        )
        let model = makeAppModel(initialItems: [item], readerProgressStore: progressStore)
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.removeSelectedItem()
        try await waitUntil { model.items.isEmpty }

        #expect(try await progressStore.progress(for: attachment.objectKey) == nil)
    }
}
