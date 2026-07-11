@testable import CitrationCore
import Foundation
import Testing

struct LibraryModelsTests {
    @Test("infers document formats from MIME type and extension")
    func documentFormatInference() {
        #expect(DocumentFormat.infer(fileName: "paper.bin", contentType: "application/pdf") == .pdf)
        #expect(DocumentFormat.infer(fileName: "book.epub") == .epub)
        #expect(DocumentFormat.infer(fileName: "notes.md") == .plainText)
        #expect(DocumentFormat.infer(fileName: "scan.heic") == .image)
    }

    @Test("reader capabilities match primary document formats")
    func readerCapabilities() {
        #expect(DocumentFormat.pdf.readerCapabilities.contains(.pageNavigation))
        #expect(DocumentFormat.pdf.readerCapabilities.contains(.annotations))
        #expect(DocumentFormat.epub.readerCapabilities.contains(.reflowableText))
        #expect(DocumentFormat.image.isReadableDocument == false)
        #expect(DocumentFormat.pdf.isSupportedInApp)
        #expect(DocumentFormat.epub.isSupportedInApp)
        #expect(DocumentFormat.html.isSupportedInApp)
        #expect(DocumentFormat.plainText.isSupportedInApp)
        #expect(!DocumentFormat.audio.isSupportedInApp)
    }

    @Test("reader progress clamps fraction complete")
    func readerProgressClampsFractionComplete() {
        let progress = ReaderProgress(
            itemID: UUID(),
            attachmentKey: "item/paper.pdf",
            location: .page(12),
            fractionComplete: 1.8
        )

        #expect(progress.id == "item/paper.pdf")
        #expect(progress.fractionComplete == 1)
    }

    @Test("collection normalizes blank and spaced names")
    func collectionNormalizesNames() {
        let named = LibraryCollection(name: "  Reading   List ")
        let untitled = LibraryCollection(name: "   ")

        #expect(named.name == "Reading List")
        #expect(untitled.name == "Untitled Collection")
    }

    @Test("collection snapshot round-trips through Codable")
    func collectionSnapshotRoundTripsThroughCodable() throws {
        let collectionID = UUID()
        let itemID = UUID()
        let snapshot = LibraryCollectionSnapshot(
            collections: [
                LibraryCollection(id: collectionID, name: "AI Papers")
            ],
            memberships: [
                LibraryCollectionMembership(collectionID: collectionID, itemID: itemID)
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LibraryCollectionSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test("item note trims text and reports empty state")
    func itemNoteTrimsTextAndReportsEmptyState() {
        let note = LibraryNote(itemID: UUID(), text: "  Remember this claim  ")
        let empty = LibraryNote(itemID: UUID(), text: "   ")

        #expect(note.text == "Remember this claim")
        #expect(!note.isEmpty)
        #expect(empty.isEmpty)
    }

    @Test("insight engine recommends local items with shared creator")
    func insightEngineRecommendsSharedCreator() {
        let sharedCreator = Creator(givenName: "Ada", familyName: "Lovelace")
        let source = BCItem(title: "Source", creators: [sharedCreator], publicationYear: 1843)
        let related = BCItem(title: "Related", creators: [sharedCreator], publicationYear: 1843)
        let unrelated = BCItem(title: "Other", creators: [Creator(familyName: "Turing")])

        let recommendations = LibraryInsightEngine().recommendations(
            for: source,
            in: [source, unrelated, related]
        )

        #expect(recommendations.map(\.candidateItemID) == [related.id])
        #expect(recommendations.first?.reasons.contains(.sharedCreator("ada lovelace")) == true)
        #expect(recommendations.first?.reasons.contains(.samePublicationYear(1843)) == true)
    }

    @Test("insight engine recommends shared topics without same-year noise")
    func insightEngineRecommendsSharedTopics() throws {
        let sourceID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let topicMatchID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let sameYearOnlyID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let source = BCItem(
            id: sourceID,
            title: "Source",
            publicationYear: 2024,
            tags: ["Machine Learning", "Vision"]
        )
        let topicMatch = BCItem(
            id: topicMatchID,
            title: "Topic Match",
            publicationYear: 2023,
            tags: [" machine   learning ", "Robotics"]
        )
        let sameYearOnly = BCItem(
            id: sameYearOnlyID,
            title: "Same Year Only",
            publicationYear: 2024
        )

        let recommendations = LibraryInsightEngine().recommendations(
            for: source,
            in: [source, sameYearOnly, topicMatch]
        )

        #expect(recommendations.map(\.candidateItemID) == [topicMatch.id])
        #expect(recommendations.first?.reasons == [.sharedTopic("machine learning")])
        #expect(RecommendationReason.sharedTopic("machine learning").displayLabel == "Shared topic: machine learning")
    }

    @Test("insight engine includes user linked relationships")
    func insightEngineIncludesUserLinkedRelationships() {
        let source = BCItem(title: "Source")
        let linked = BCItem(title: "Linked")
        let relationship = LibraryRelationship(
            sourceItemID: source.id,
            targetItemID: linked.id,
            kind: .series,
            confidence: 1,
            note: "  Read together  "
        )

        let recommendations = LibraryInsightEngine().recommendations(
            for: source,
            in: [source, linked],
            relationships: [relationship]
        )

        #expect(recommendations.map(\.candidateItemID) == [linked.id])
        #expect(recommendations.first?.reasons == [.userLinked(.series)])
        #expect(relationship.note == "Read together")
        #expect(LibraryRelationshipKind.sameCreator.displayLabel == "Same author")
    }

    @Test("work discovery suggestion creates library item")
    func workDiscoverySuggestionCreatesLibraryItem() {
        let suggestion = WorkDiscoverySuggestion(
            providerName: "openalex",
            providerRecordID: "https://openalex.org/W1",
            title: "  Related   Work  ",
            creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
            publicationYear: 1843,
            itemType: .article,
            identifiers: [Identifier(type: .doi, value: "10.5555/example")],
            sourceURL: URL(string: "https://openalex.org/W1"),
            confidence: 1.4,
            reasons: [.openAlexRelatedWork("W0")]
        )

        let item = suggestion.makeLibraryItem(createdAt: Date(timeIntervalSince1970: 1))

        #expect(suggestion.id == "https://openalex.org/W1")
        #expect(suggestion.title == "Related Work")
        #expect(suggestion.confidence == 1)
        #expect(item.title == "Related Work")
        #expect(item.identifiers == [Identifier(type: .doi, value: "10.5555/example")])
        #expect(item.publicationYear == 1843)
        #expect(item.itemType == .article)
    }

    @Test("annotation trims note text and reports empty state")
    func annotationTrimsNoteTextAndReportsEmptyState() {
        let annotation = LibraryAnnotation(
            itemID: UUID(),
            attachmentKey: "item/paper.pdf",
            note: "  Important margin note  "
        )

        #expect(annotation.note == "Important margin note")
        #expect(!annotation.isEmpty)
    }

    @Test("annotation round-trips through Codable")
    func annotationRoundTripsThroughCodable() throws {
        let annotation = LibraryAnnotation(
            itemID: UUID(),
            attachmentKey: "item/paper.pdf",
            location: .page(4),
            selectedText: "A useful quote",
            note: "Check this claim",
            color: .blue,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let data = try JSONEncoder().encode(annotation)
        let decoded = try JSONDecoder().decode(LibraryAnnotation.self, from: data)

        #expect(decoded == annotation)
    }
}
