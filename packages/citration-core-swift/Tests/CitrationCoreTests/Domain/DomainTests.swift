@testable import CitrationCore
import Foundation
import Testing

@Suite("BCItem")
struct DomainTests {
    @Test("doi computed property reads from identifiers")
    func doiComputedProperty() {
        let item = BCItem(
            title: "Test",
            identifiers: [Identifier(type: .doi, value: "10.1234/test")]
        )
        #expect(item.doi == "10.1234/test")
    }

    @Test("doi returns nil when no DOI identifier present")
    func doiReturnsNilWhenMissing() {
        let item = BCItem(
            title: "Test",
            identifiers: [Identifier(type: .isbn, value: "978-0-13-468599-1")]
        )
        #expect(item.doi == nil)
    }

    @Test("item tags are trimmed and deduplicated case-insensitively")
    func itemTagsAreNormalized() {
        let item = BCItem(
            title: "Tagged",
            tags: ["  Machine   Learning ", "machine learning", "", " Vision\nSystems "]
        )

        #expect(item.tags == ["Machine Learning", "Vision Systems"])
    }

    @Test("decoding legacy items without tags defaults to empty tags")
    func decodingLegacyItemsDefaultsTags() throws {
        let legacyJSON = """
        {
          "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "title": "Legacy",
          "identifiers": [],
          "itemType": "article",
          "creators": [],
          "createdAt": 0,
          "updatedAt": 0
        }
        """

        let item = try JSONDecoder().decode(BCItem.self, from: Data(legacyJSON.utf8))

        #expect(item.tags.isEmpty)
    }
}
