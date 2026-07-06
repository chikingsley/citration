@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("CSL citation formatter")
struct CSLCitationFormatterTests {
    // MARK: Internal

    @Test("APA bibliography entry renders author, year, and title")
    func apaBibliographyEntry() async throws {
        let formatter = CSLCitationFormatter()
        let bibliography = try await formatter.formatBibliography(
            items: [Self.paper],
            style: CitationStyle(id: "apa", title: "APA"),
            options: CitationRenderOptions(format: .plainText)
        )

        let entry = try #require(bibliography.entries.first)
        #expect(entry.contains("Lovelace"))
        #expect(entry.contains("1843"))
        #expect(entry.contains("On a great subject"))
        #expect(entry.contains("10.1234/example"))
    }

    @Test("APA in-text citation renders (Author, Year)")
    func apaInTextCitation() async throws {
        let formatter = CSLCitationFormatter()
        let cluster = CitationCluster(items: [CitationItem(itemID: Self.paper.id)])
        let output = try await formatter.formatCluster(
            cluster,
            items: [Self.paper],
            style: CitationStyle(id: "apa", title: "APA"),
            options: CitationRenderOptions(format: .plainText)
        )

        #expect(output.text == "(Lovelace, 1843)")
    }

    @Test("Chicago author-date style renders distinctly")
    func chicagoBibliographyEntry() async throws {
        let formatter = CSLCitationFormatter()
        let bibliography = try await formatter.formatBibliography(
            items: [Self.paper],
            style: CitationStyle(id: "chicago-author-date", title: "Chicago"),
            options: CitationRenderOptions(format: .plainText)
        )

        let entry = try #require(bibliography.entries.first)
        #expect(entry.contains("Lovelace"))
        #expect(entry.contains("1843"))
    }

    @Test("unknown style throws a descriptive error")
    func unknownStyleThrows() async {
        let formatter = CSLCitationFormatter()
        await #expect(throws: CitationEngineError.self) {
            _ = try await formatter.formatBibliography(
                items: [Self.paper],
                style: CitationStyle(id: "no-such-style", title: "Nope"),
                options: CitationRenderOptions(format: .plainText)
            )
        }
    }

    // MARK: Private

    private static let paper: BCItem = .init(
        title: "On a great subject",
        identifiers: [Identifier(type: .doi, value: "10.1234/example")],
        itemType: .article,
        creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
        publicationYear: 1843
    )
}
