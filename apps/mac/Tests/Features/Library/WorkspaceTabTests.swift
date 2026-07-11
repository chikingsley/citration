@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("Workspace tabs")
@MainActor
struct WorkspaceTabTests {
    // MARK: Internal

    @Test("Library remains available while document tabs open, switch, and close")
    func libraryAndDocumentLifecycle() throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let firstURL = try makeFile(named: "first.pdf", contents: Data("first".utf8), in: directory)
        let secondURL = try makeFile(named: "second.epub", contents: Data("second".utf8), in: directory)
        let item = BCItem(title: "Workspace Item")
        let model = makeAppModel(initialItems: [item])
        let first = attachment(itemID: item.id, key: "FIRST001", url: firstURL, contentType: "application/pdf")
        let second = attachment(
            itemID: item.id,
            key: "SECOND01",
            url: secondURL,
            contentType: "application/epub+zip"
        )

        #expect(model.selectedWorkspaceTab == .library)
        model.openDocument(first)
        model.openDocument(first)
        #expect(model.openDocuments == [first])
        #expect(model.selectedWorkspaceTab == .document(first.objectKey))
        #expect(model.reader.activeAttachment == first)

        model.openDocument(second)
        #expect(model.openDocuments == [first, second])
        #expect(model.selectedWorkspaceTab == .document(second.objectKey))
        model.closeDocument(attachmentKey: second.objectKey)
        #expect(model.openDocuments == [first])
        #expect(model.selectedWorkspaceTab == .document(first.objectKey))
        #expect(model.reader.activeAttachment == first)

        model.selectWorkspaceTab(.library)
        #expect(model.selectedWorkspaceTab == .library)
        #expect(model.reader.activeAttachment == nil)
        model.closeDocument(attachmentKey: first.objectKey)
        #expect(model.openDocuments.isEmpty)
        #expect(model.selectedWorkspaceTab == .library)
    }

    @Test("Detached-window routes preserve a real local attachment")
    func detachedRouteRoundTrip() throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let fileURL = try makeFile(named: "document.pdf", contents: Data("document".utf8), in: directory)
        let source = attachment(
            itemID: UUID(),
            key: "DETACH01",
            url: fileURL,
            contentType: "application/pdf"
        )
        let encoded = try JSONEncoder().encode(DocumentWindowRoute(attachment: source))
        let decoded = try JSONDecoder().decode(DocumentWindowRoute.self, from: encoded)

        #expect(decoded.attachment == source)
        #expect(FileManager.default.fileExists(atPath: decoded.localURL.path))
    }

    // MARK: Private

    private func attachment(
        itemID: UUID,
        key: String,
        url: URL,
        contentType: String
    ) -> LocalAttachment {
        LocalAttachment(
            itemID: itemID,
            fileName: url.lastPathComponent,
            objectKey: key,
            localURL: url,
            contentType: contentType,
            size: Int64((try? Data(contentsOf: url).count) ?? 0),
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}
