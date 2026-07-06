@testable import Citration
import CitrationCore
import Foundation
import Testing

/// Exercises the extraction pipeline against real documents from the
/// library export: born-digital papers, a full textbook in PDF and
/// EPUB form, and a scanned book with no text layer.
@Suite("Real document fixtures")
struct RealDocumentFixtureTests {
    // MARK: Internal

    @Test("finds the DOI printed in a born-digital paper")
    func findsDOIInBornDigitalPaper() async {
        let candidates = await PDFKitDOIExtractor()
            .extractCandidates(from: Self.fixture("efl-drama-paper.pdf"))
        #expect(candidates.detectedDOI == "10.1186/s40862-026-00398-5")
    }

    @Test("finds the DOI in a journal-archive paper")
    func findsDOIInJournalArchivePaper() async {
        let candidates = await PDFKitDOIExtractor()
            .extractCandidates(from: Self.fixture("mongol-costumes-paper.pdf"))
        #expect(candidates.detectedDOI == "10.1080/02529203.2018.1414417")
    }

    @Test("textbook yields its book-level DOI first plus ISBNs")
    func textbookYieldsBookIdentifiers() async {
        let candidates = await PDFKitDOIExtractor()
            .extractCandidates(from: Self.fixture("language-learning-theories.pdf"))
        #expect(candidates.detectedDOI == "10.1007/978-3-031-92210-7")
        let isbns = candidates.identifiers.filter { $0.type == .isbn }.map(\.value)
        #expect(isbns.contains("9783031922107"))
    }

    /// A 67-page scan with no text layer comes back with zero
    /// candidates — the detectable signal for a future OCR pass.
    @Test("scanned book with no text layer yields no candidates")
    func scannedBookYieldsNoCandidates() async {
        let candidates = await PDFKitDOIExtractor()
            .extractCandidates(from: Self.fixture("kabul-persian-scanned.pdf"))
        #expect(candidates.isEmpty)
        #expect(candidates.detectedDOI == nil)
        #expect(candidates.titleHints.isEmpty)
    }

    @Test("EPUB package parses and reports its title")
    func epubPublicationParses() throws {
        let publication = try EPUBPackageReader()
            .publication(from: Self.fixture("language-learning-theories.epub"))
        #expect(publication.title == "Language Learning Theories")
    }

    // MARK: Private

    private static func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }
}
