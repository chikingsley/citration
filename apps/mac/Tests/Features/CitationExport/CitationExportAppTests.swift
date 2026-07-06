@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - CitationExportAppTests

@Suite("Citation Export")
@MainActor
struct CitationExportAppTests {
    @Test("exportSelectedCitation prepares CSL JSON")
    func exportSelectedCitationPreparesCSLJSON() async {
        let item = BCItem(
            title: "Paper",
            identifiers: [Identifier(type: .doi, value: "10.1234/example")],
            itemType: .article,
            creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
            publicationYear: 1843
        )
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.citation.exportSelected(format: .cslJSON)

        #expect(model.citation.exportFormat == .cslJSON)
        #expect(model.citation.exportText.contains("\"DOI\" : \"10.1234/example\""))
        #expect(model.citation.exportText.contains("\"title\" : \"Paper\""))
        #expect(model.statusMessage == "Prepared CSL JSON")
    }

    @Test("exportSelectedCitation prepares BibTeX and clears on item change")
    func exportSelectedCitationPreparesBibTeXAndClearsOnItemChange() async {
        let first = BCItem(
            title: "Paper",
            identifiers: [Identifier(type: .doi, value: "10.1234/example")],
            itemType: .article,
            creators: [Creator(familyName: "Lovelace")],
            publicationYear: 1843
        )
        let second = BCItem(title: "Other")
        let model = makeAppModel(initialItems: [first, second])
        await model.refreshItems()
        model.selectItem(id: first.id)

        model.citation.exportSelected(format: .bibTeX)
        #expect(model.citation.exportText.contains("@article{lovelace1843paper,"))

        model.selectItem(id: second.id)
        #expect(model.citation.exportText.isEmpty)
    }
}
