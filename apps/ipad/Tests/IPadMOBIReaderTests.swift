@testable import CitrationPad
import Foundation
import Testing

// MARK: - IPadMOBIReaderTests

@Suite("iPad MOBI reader")
struct IPadMOBIReaderTests {
    @Test("opens a real unencrypted classic MOBI publication")
    func opensRealMOBI() throws {
        let url = try #require(Bundle(for: FixtureBundleToken.self).url(
            forResource: "sample-unicode-uncompressed",
            withExtension: "mobi"
        ))
        let document = try MOBIDocumentReader.read(from: url)

        #expect(document.title == "Libmobi test sample")
        #expect(document.html.contains("This is a sample for testing libmobi project."))
        #expect(document.html.contains("<html>"))
    }
}

// MARK: - FixtureBundleToken

private final class FixtureBundleToken {}
