import Foundation
import Testing
@testable import CitrationCore

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
    }

    @Test("reader progress clamps fraction complete")
    func readerProgressClampsFractionComplete() {
        let progress = ReaderProgress(
            attachmentID: UUID(),
            location: .page(12),
            fractionComplete: 1.8
        )

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
