@testable import CitrationPad
import Foundation
import Testing

@Suite("iPad cached documents")
struct IPadCachedDocumentTests {
    // MARK: Internal

    @Test("loads a real HTML snapshot with the shared offline policy")
    func secureHTMLSnapshot() throws {
        let fixture = Self.fixture("offline-snapshot.html")

        let document = try CachedHTMLDocument(fileURL: fixture)

        #expect(document.html.contains("This local HTML snapshot is a real reader fixture."))
        #expect(document.html.contains(CachedHTMLDocument.contentSecurityPolicy))
        #expect(CachedHTMLDocument.contentSecurityPolicy.contains("connect-src 'none'"))
        #expect(CachedHTMLDocument.contentSecurityPolicy.contains("frame-src 'none'"))
    }

    @Test("loads the real text fixture with encoding detection")
    func plainText() throws {
        let document = try CachedPlainTextDocument(fileURL: Self.fixture("reading-notes.txt"))

        #expect(document.text.contains("Résumé notes remain selectable"))
        #expect(document.text.contains("line breaks are preserved"))
    }

    // MARK: Private

    private static func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "mac/Tests/Fixtures/\(name)")
    }
}
