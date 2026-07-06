@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("OpenLibrary title search")
struct OpenLibraryTitleSearchTests {
    // MARK: Internal

    @Test("maps the matching doc into a book record")
    func mapsMatchingDoc() throws {
        let records = OpenLibraryTitleSearchMetadataProvider.records(
            fromSearchData: Data(Self.kabulResponse.utf8),
            query: "PERSIAN AN INTRODUCTION TO COLLOQUIAL KABUL PERSIAN",
            providerName: "openlibrary-title"
        )

        let record = try #require(records.first)
        #expect(record.title == "An introduction to colloquial Kabul Persian")
        #expect(record.publicationYear == 1966)
        #expect(record.itemType == .book)
        #expect(record.creators.first?.displayName == "Defense Language Institute")
        #expect(record.identifiers.isEmpty)
        #expect(record.confidence == 0.65)
    }

    @Test("skips docs whose titles do not resemble the query")
    func skipsDissimilarDocs() {
        let records = OpenLibraryTitleSearchMetadataProvider.records(
            fromSearchData: Data(Self.unrelatedResponse.utf8),
            query: "PERSIAN AN INTRODUCTION TO COLLOQUIAL KABUL PERSIAN",
            providerName: "openlibrary-title"
        )
        #expect(records.isEmpty)
    }

    @Test("normalizes the first valid ISBN when present")
    func normalizesISBN() throws {
        let records = OpenLibraryTitleSearchMetadataProvider.records(
            fromSearchData: Data(Self.isbnResponse.utf8),
            query: "Language Learning Theories",
            providerName: "openlibrary-title"
        )

        let record = try #require(records.first)
        #expect(record.identifiers == [Identifier(type: .isbn, value: "9780306406157")])
    }

    // MARK: Private

    /// Mirrors the real search.json response for the 1966 DLI book.
    private static let kabulResponse = """
    {
      "docs": [
        {
          "key": "/works/OL12345W",
          "title": "An introduction to colloquial Kabul Persian",
          "author_name": ["Defense Language Institute"],
          "first_publish_year": 1966
        }
      ]
    }
    """

    private static let unrelatedResponse = """
    {
      "docs": [
        {
          "key": "/works/OL99999W",
          "title": "Colloquial Persian",
          "author_name": ["Abdi Rafiee"],
          "first_publish_year": 2001
        }
      ]
    }
    """

    private static let isbnResponse = """
    {
      "docs": [
        {
          "key": "/works/OL55555W",
          "title": "Language Learning Theories",
          "isbn": ["invalid-isbn", "978-0-306-40615-7"],
          "first_publish_year": 2025
        }
      ]
    }
    """
}
