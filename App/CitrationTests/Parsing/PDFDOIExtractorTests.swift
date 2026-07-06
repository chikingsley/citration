@testable import Citration
import Foundation
import Testing

@Suite("PDF DOI Parsing")
struct PDFDOIExtractorTests {
    // MARK: Internal

    @Test("candidates normalizes DOI from noisy text")
    func candidatesNormalizesDOIFromNoisyText() {
        let text = """
        See DOI: 10.1038/NATURE12373).
        Duplicate mention: 10.1038/nature12373
        """

        let candidates = DOIParsing.candidates(in: text)
        #expect(candidates == ["10.1038/nature12373"])
    }

    @Test("normalizeCandidate rejects malformed DOI")
    func normalizeCandidateRejectsMalformedDOI() {
        #expect(DOIParsing.normalizeCandidate("doi:10.abc/not-valid") == nil)
    }

    @Test("ArXiv parsing normalizes and removes version suffix")
    func arXivParsingNormalizesVersionedCandidate() {
        let text = """
        Results are available at arXiv:2401.01234v2 and a legacy ID hep-th/9901001v3.
        """

        let candidates = ArXivParsing.candidates(in: text)
        #expect(candidates == ["2401.01234", "hep-th/9901001"])
    }

    @Test("ISBN parsing extracts valid ISBN and rejects malformed")
    func isbnParsingExtractsValidISBN() {
        let text = """
        ISBN-13: 978-0-306-40615-7
        ISBN: 123-4-567-89012-3
        """

        let candidates = ISBNParsing.candidates(in: text)
        #expect(candidates == ["9780306406157"])
        #expect(ISBNParsing.normalizeCandidate("123-4-567-89012-3") == nil)
    }

    @Test(
        "MuPDF extractor finds DOI from sample PDF",
        .enabled(if: FileManager.default.isExecutableFile(atPath: Self.mutoolPath)),
        .enabled(if: FileManager.default.fileExists(atPath: Self.samplePDF.path))
    )
    func muPDFExtractorFindsDOIFromSamplePDF() async {
        let extractor = MuPDFDOIExtractor(
            executableURL: URL(fileURLWithPath: Self.mutoolPath),
            allowPDFKitFallback: false
        )
        let doi = await extractor.extractDOI(from: Self.samplePDF)
        #expect(doi == "10.1371/journal.pntd.0003350")
    }

    // MARK: Private

    private static let mutoolPath = "/opt/homebrew/bin/mutool"

    /// Sample fixture lives in a sibling checkout (~/GitHub/test); the test is
    /// skipped when it or mutool is absent.
    private static let samplePDF = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("test/tests/data/recognizePDF_test_DOI.pdf")
}
