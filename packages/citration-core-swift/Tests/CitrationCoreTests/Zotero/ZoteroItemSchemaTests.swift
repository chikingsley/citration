@testable import CitrationCore
import Foundation
import Testing

@Suite("Zotero item editing schema")
struct ZoteroItemSchemaTests {
    // MARK: Internal

    @Test("Captured self-host schema responses decode with fields and creator roles")
    func capturedSchemaResponsesDecode() throws {
        let itemTypes = try JSONDecoder().decode(
            [ZoteroItemTypeDefinition].self,
            from: Data(Self.itemTypesJSON.utf8)
        )
        let fields = try JSONDecoder().decode(
            [ZoteroItemFieldDefinition].self,
            from: Data(Self.bookFieldsJSON.utf8)
        )
        let creatorTypes = try JSONDecoder().decode(
            [ZoteroCreatorTypeDefinition].self,
            from: Data(Self.bookCreatorTypesJSON.utf8)
        )
        let book = try #require(itemTypes.first { $0.itemType == "book" })
        let schema = ZoteroItemEditingSchema(
            itemType: book,
            fields: fields,
            creatorTypes: creatorTypes
        )

        #expect(schema.itemType.localized == "Book")
        #expect(schema.fields.map(\.field) == ["title", "abstractNote", "publisher", "DOI"])
        #expect(schema.creatorTypes.map(\.creatorType) == ["author", "contributor", "editor"])
        #expect(schema.primaryCreatorType == "author")
    }

    // MARK: Private

    private static let itemTypesJSON = #"""
    [
      {"itemType":"book","localized":"Book"},
      {"itemType":"conferencePaper","localized":"Conference Paper"},
      {"itemType":"journalArticle","localized":"Journal Article"},
      {"itemType":"preprint","localized":"Preprint"}
    ]
    """#

    private static let bookFieldsJSON = #"""
    [
      {"field":"title","localized":"Title"},
      {"field":"abstractNote","localized":"Abstract Note"},
      {"field":"publisher","localized":"Publisher"},
      {"field":"DOI","localized":"DOI"}
    ]
    """#

    private static let bookCreatorTypesJSON = #"""
    [
      {"creatorType":"author","localized":"Author","primary":true},
      {"creatorType":"contributor","localized":"Contributor"},
      {"creatorType":"editor","localized":"Editor"}
    ]
    """#
}
