import Testing
import Foundation
@testable import Citration
import CitrationCore

@Suite("Citation Export")
@MainActor
struct CitationExportAppTests {
    @Test("exportSelectedCitation prepares CSL JSON")
    func exportSelectedCitationPreparesCSLJSON() async throws {
        let item = BCItem(
            title: "Paper",
            identifiers: [Identifier(type: .doi, value: "10.1234/example")],
            itemType: .article,
            creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
            publicationYear: 1843
        )
        let model = makeModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)

        model.exportSelectedCitation(format: .cslJSON)

        #expect(model.citationExportFormat == .cslJSON)
        #expect(model.citationExportText.contains("\"DOI\" : \"10.1234/example\""))
        #expect(model.citationExportText.contains("\"title\" : \"Paper\""))
        #expect(model.statusMessage == "Prepared CSL JSON")
    }

    @Test("exportSelectedCitation prepares BibTeX and clears on item change")
    func exportSelectedCitationPreparesBibTeXAndClearsOnItemChange() async throws {
        let first = BCItem(
            title: "Paper",
            identifiers: [Identifier(type: .doi, value: "10.1234/example")],
            itemType: .article,
            creators: [Creator(familyName: "Lovelace")],
            publicationYear: 1843
        )
        let second = BCItem(title: "Other")
        let model = makeModel(initialItems: [first, second])
        await model.refreshItems()
        model.selectItem(id: first.id)

        model.exportSelectedCitation(format: .bibTeX)
        #expect(model.citationExportText.contains("@article{lovelace1843paper,"))

        model.selectItem(id: second.id)
        #expect(model.citationExportText.isEmpty)
    }
}

private extension CitationExportAppTests {
    func makeModel(initialItems: [BCItem]) -> AppModel {
        AppModel(
            store: InMemoryItemStore(initialItems: initialItems),
            metadataRegistry: MetadataProviderRegistry(providers: [NoopMetadataProvider()]),
            citationFormatter: StubCitationFormatter(),
            storageConnectors: [],
            pdfDOIExtractor: NullPDFDOIExtractor(),
            attachmentStore: nil,
            annotationStore: makeAnnotationStore(),
            collectionStore: makeCollectionStore(),
            noteStore: makeNoteStore(),
            relationshipStore: makeRelationshipStore(),
            readerProgressStore: makeReaderProgressStore()
        )
    }

    func makeAnnotationStore() -> LocalAnnotationStore? {
        try? LocalAnnotationStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-citation-export-annotations")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeCollectionStore() -> LocalCollectionStore? {
        try? LocalCollectionStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-citation-export-collections")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeNoteStore() -> LocalNoteStore? {
        try? LocalNoteStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-citation-export-notes")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeRelationshipStore() -> LocalRelationshipStore? {
        try? LocalRelationshipStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-citation-export-relationships")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeReaderProgressStore() -> LocalReaderProgressStore? {
        try? LocalReaderProgressStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-citation-export-reader-progress")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }
}
