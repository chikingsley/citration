import Foundation
import Testing
@testable import CitrationCore

@Suite("CitationExporter")
struct CitationExportTests {
    @Test("exports CSL JSON from bibliographic item")
    func exportsCSLJSONFromBibliographicItem() throws {
        let item = BCItem(
            id: try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
            title: "  A   Great   Paper  ",
            identifiers: [
                Identifier(type: .doi, value: "10.1234/example"),
                Identifier(type: .url, value: "https://example.test/paper")
            ],
            itemType: .article,
            creators: [
                Creator(givenName: "Ada", familyName: "Lovelace"),
                Creator(literalName: "Citration Lab")
            ],
            publicationYear: 1843
        )

        let json = try CitationExporter().cslJSON(for: [item])

        #expect(json.contains("\"type\" : \"article-journal\""))
        #expect(json.contains("\"title\" : \"A Great Paper\""))
        #expect(json.contains("\"family\" : \"Lovelace\""))
        #expect(json.contains("\"literal\" : \"Citration Lab\""))
        #expect(json.contains("\"DOI\" : \"10.1234/example\""))
        #expect(json.contains("\"date-parts\" : ["))
    }

    @Test("exports BibTeX with stable citation key")
    func exportsBibTeXWithStableCitationKey() {
        let item = BCItem(
            title: "A Great Paper",
            identifiers: [
                Identifier(type: .doi, value: "10.1234/example"),
                Identifier(type: .arxiv, value: "2401.12345")
            ],
            itemType: .preprint,
            creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
            publicationYear: 1843
        )

        let bibTeX = CitationExporter().bibTeX(for: [item])

        #expect(bibTeX.contains("@article{lovelace1843agreatpaper,"))
        #expect(bibTeX.contains("author = {Lovelace, Ada}"))
        #expect(bibTeX.contains("doi = {10.1234/example}"))
        #expect(bibTeX.contains("eprint = {2401.12345}"))
        #expect(bibTeX.contains("archivePrefix = {arXiv}"))
    }

    @Test("deduplicates BibTeX keys")
    func deduplicatesBibTeXKeys() {
        let first = BCItem(title: "Same", creators: [Creator(familyName: "Author")], publicationYear: 2024)
        let second = BCItem(title: "Same", creators: [Creator(familyName: "Author")], publicationYear: 2024)

        let bibTeX = CitationExporter().bibTeX(for: [first, second])

        #expect(bibTeX.contains("@misc{author2024same,"))
        #expect(bibTeX.contains("@misc{author2024same2,"))
    }
}
