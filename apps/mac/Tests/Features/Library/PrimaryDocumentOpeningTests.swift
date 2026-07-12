@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("Primary document opening")
@MainActor
struct PrimaryDocumentOpeningTests {
    @Test("primary open resolves and opens the only readable attachment")
    func primaryOpenResolvesOnlyReadableAttachment() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let source = try makeFile(named: "paper.pdf", contents: Data("pdf".utf8), in: directory)
        let store = try LocalAttachmentStore(
            baseDirectory: directory.appending(path: "attachments", directoryHint: .isDirectory)
        )
        let item = BCItem(title: "Open Me")
        let attachment = try await store.importFile(from: source, for: item)
        let model = makeAppModel(initialItems: [item], attachmentStore: store)
        await model.refreshItems()
        let identity = try #require(model.items.first?.identity)

        model.openPrimaryDocument(for: identity)
        try await waitUntil { model.documentSessions.count == 1 }

        #expect(model.documentSessions.first?.attachment.objectKey == attachment.objectKey)
        #expect(model.documentSessions.first?.attachment.fileName == attachment.fileName)
        #expect(model.selectedWorkspaceTab == .document(attachment.objectKey))
    }

    @Test("primary open asks the user when several readable attachments exist")
    func primaryOpenOffersReadableAttachmentChoices() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let pdf = try makeFile(named: "paper.pdf", contents: Data("pdf".utf8), in: directory)
        let epub = try makeFile(named: "book.epub", contents: Data("epub".utf8), in: directory)
        let store = try LocalAttachmentStore(
            baseDirectory: directory.appending(path: "attachments", directoryHint: .isDirectory)
        )
        let item = BCItem(title: "Choose Me")
        _ = try await store.importFile(from: epub, for: item)
        _ = try await store.importFile(from: pdf, for: item)
        let model = makeAppModel(initialItems: [item], attachmentStore: store)
        await model.refreshItems()
        let identity = try #require(model.items.first?.identity)

        model.openPrimaryDocument(for: identity)
        try await waitUntil { model.pendingReadableAttachmentChoices.count == 2 }

        #expect(model.documentSessions.isEmpty)
        #expect(model.pendingReadableAttachmentChoices.map(\.documentFormat) == [.pdf, .epub])
    }

    @Test("drag payload round-trips all selected item identifiers")
    func dragPayloadRoundTripsIdentifiers() throws {
        let ids = [UUID(), UUID(), UUID()]

        let decoded = try #require(LibraryItemDragPayload.decode(LibraryItemDragPayload.encode(ids)))

        #expect(Set(decoded) == Set(ids))
    }
}
