import Testing
import Foundation
@testable import BetterCiteMac
import BCDomain
import BCCommon

@Suite("LocalAttachmentStore")
struct AttachmentStoreTests {
    @Test("import uses readable deterministic naming")
    func importUsesReadableDeterministicNaming() async throws {
        let baseDirectory = makeTempDirectory()
        defer { cleanupDirectory(baseDirectory) }

        let sourceURL = try makeFile(named: "random-input.pdf", contents: Data("hello".utf8), in: baseDirectory)
        let store = try LocalAttachmentStore(baseDirectory: baseDirectory.appendingPathComponent("attachments", isDirectory: true))
        let item = BCItem(
            title: "Nanometre Scale Thermometry",
            creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
            publicationYear: 1843
        )

        let attachment = try await store.importFile(from: sourceURL, for: item)

        #expect(attachment.fileName == "lovelace_1843_nanometre-scale-thermometry.pdf")
        #expect(FileManager.default.fileExists(atPath: attachment.localURL.path))
        #expect(attachment.objectKey.hasPrefix("\(item.id.uuidString)/"))
    }

    @Test("import deduplicates filename with numeric suffix")
    func importDeduplicatesFilename() async throws {
        let baseDirectory = makeTempDirectory()
        defer { cleanupDirectory(baseDirectory) }

        let sourceURL = try makeFile(named: "paper.pdf", contents: Data("hello".utf8), in: baseDirectory)
        let store = try LocalAttachmentStore(baseDirectory: baseDirectory.appendingPathComponent("attachments", isDirectory: true))
        let item = BCItem(title: "Untitled Item")

        let first = try await store.importFile(from: sourceURL, for: item)
        let second = try await store.importFile(from: sourceURL, for: item)

        #expect(first.fileName == "paper.pdf")
        #expect(second.fileName == "paper-2.pdf")
    }

    @Test("listAttachments reads persisted files for item")
    func listAttachmentsReadsPersistedFiles() async throws {
        let baseDirectory = makeTempDirectory()
        defer { cleanupDirectory(baseDirectory) }

        let sourceURL = try makeFile(named: "paper.pdf", contents: Data("hello".utf8), in: baseDirectory)
        let attachmentsDirectory = baseDirectory.appendingPathComponent("attachments", isDirectory: true)
        let firstStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)
        let item = BCItem(title: "Persistent Item")

        _ = try await firstStore.importFile(from: sourceURL, for: item)

        let secondStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)
        let attachments = try await secondStore.listAttachments(for: item.id)

        #expect(attachments.count == 1)
        #expect(attachments.first?.fileName == "persistent-item.pdf")
    }

    @Test("removeAttachment deletes persisted file")
    func removeAttachmentDeletesPersistedFile() async throws {
        let baseDirectory = makeTempDirectory()
        defer { cleanupDirectory(baseDirectory) }

        let sourceURL = try makeFile(named: "paper.pdf", contents: Data("hello".utf8), in: baseDirectory)
        let attachmentsDirectory = baseDirectory.appendingPathComponent("attachments", isDirectory: true)
        let store = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)
        let item = BCItem(title: "Delete Test")

        let attachment = try await store.importFile(from: sourceURL, for: item)
        try await store.removeAttachment(attachment)
        let attachments = try await store.listAttachments(for: item.id)

        #expect(attachments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: attachment.localURL.path))
    }
}

private extension AttachmentStoreTests {
    func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("better-cite-tests", isDirectory: true)
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
}
