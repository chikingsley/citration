import CitrationCore
@testable import CitrationPad
import Foundation
import Testing

// MARK: - IPadEPUBReaderTests

@Suite("iPad EPUB reader")
struct IPadEPUBReaderTests {
    // MARK: Internal

    @Test("extracts the real EPUB fixture inside an app sandbox")
    func extractsRealPackage() throws {
        let fixture = Self.fixture
        #expect(FileManager.default.fileExists(atPath: fixture.path))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "citration-ipad-epub-tests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let publication = try EPUBPackageReader(unpackRoot: directory).publication(from: fixture)

        #expect(publication.readingOrder.count > 1)
        #expect(!publication.tableOfContents.isEmpty)
        #expect(FileManager.default.fileExists(atPath: publication.initialDocumentURL.path))
        #expect(publication.search("Constructivism").isEmpty == false)
    }

    @Test("reader cleanup removes its extracted package")
    @MainActor
    func readerCleanup() throws {
        let state = EPUBReaderState()
        state.load(
            attachment: LibraryAttachment(
                itemID: UUID(),
                fileName: Self.fixture.lastPathComponent,
                objectKey: "EPUBTEST",
                localURL: Self.fixture,
                contentType: "application/epub+zip",
                size: 0,
                createdAt: .now
            ),
            progress: nil
        )
        let root = try #require(state.publication?.rootDirectory)
        #expect(FileManager.default.fileExists(atPath: root.path))

        state.reset()

        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    // MARK: Private

    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "mac/Tests/Fixtures/language-learning-theories.epub")
}
