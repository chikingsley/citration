@testable import Citration
import Foundation
import PDFKit
import Testing

@Suite("Cached document readers")
struct CachedDocumentReaderTests {
    // MARK: Internal

    @Test("all supported readers consume real local files")
    func allSupportedReadersConsumeRealFiles() throws {
        let pdfURL = Self.fixture("efl-drama-paper.pdf")
        let epubURL = Self.fixture("language-learning-theories.epub")
        let htmlURL = Self.fixture("offline-snapshot.html")
        let textURL = Self.fixture("reading-notes.txt")

        let pdf = try #require(PDFDocument(url: pdfURL))
        let epub = try EPUBPackageReader().publication(from: epubURL)
        defer { try? FileManager.default.removeItem(at: epub.rootDirectory) }
        let html = try CachedHTMLDocument(fileURL: htmlURL)
        let text = try CachedPlainTextDocument(fileURL: textURL)

        #expect(pdf.pageCount > 0)
        #expect(epub.title == "Language Learning Theories")
        #expect(html.baseURL == htmlURL.deletingLastPathComponent())
        #expect(html.html.contains("Offline article"))
        #expect(html.html.contains(CachedHTMLDocument.contentSecurityPolicy))
        #expect(text.text.contains("Résumé notes remain selectable"))
        #expect(text.text.contains("line breaks are preserved"))
    }

    @Test("HTML snapshots disable script and persistent website state")
    @MainActor
    func htmlSnapshotsDisableActiveContent() {
        let configuration = HTMLSnapshotReaderView.makeConfiguration()

        #expect(!configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(!configuration.websiteDataStore.isPersistent)
        #expect(CachedHTMLDocument.contentSecurityPolicy.contains("connect-src 'none'"))
        #expect(CachedHTMLDocument.contentSecurityPolicy.contains("object-src 'none'"))
    }

    @Test("HTML tag matching does not mistake header content for a head element")
    func htmlTagMatchingUsesExactElementNames() throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let fragmentURL = directory.appending(path: "fragment.html")
        try "<header>Article header</header><main>Article body</main>"
            .write(to: fragmentURL, atomically: true, encoding: .utf8)

        let document = try CachedHTMLDocument(fileURL: fragmentURL)

        #expect(document.html.hasPrefix("<!doctype html><html><head>"))
        #expect(document.html.contains("<body><header>Article header</header>"))
    }

    // MARK: Private

    private static func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/\(name)")
    }
}
