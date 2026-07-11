@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("AppModel reader")
@MainActor
struct AppModelReaderTests {
    @Test("opening PDF reader tracks attachment and selected item")
    func openingPDFReaderTracksAttachmentAndSelectedItem() async {
        let item = BCItem(title: "Reader Item")
        let attachment = makeAttachment(
            itemID: item.id,
            fileName: "reader.pdf",
            contentType: "application/pdf"
        )
        let model = makeAppModel(initialItems: [item], providers: [NoopMetadataProvider()])
        await model.refreshItems()

        model.reader.open(attachment)

        #expect(model.reader.activeAttachment == attachment)
        #expect(model.selectedItemID == item.id)
        #expect(model.statusMessage == "Reading reader.pdf")
    }

    @Test("opening EPUB reader starts in-app reading")
    func openingEPUBReaderStartsInAppReading() {
        let attachment = makeAttachment(
            itemID: UUID(),
            fileName: "book.epub",
            contentType: "application/epub+zip"
        )
        let model = makeAppModel(providers: [NoopMetadataProvider()])

        model.reader.open(attachment)

        #expect(model.reader.activeAttachment == attachment)
        #expect(model.statusMessage == "Reading book.epub")
    }

    @Test("opening HTML and text starts explicit in-app reading")
    func openingHTMLAndTextStartsInAppReading() {
        let itemID = UUID()
        let html = makeAttachment(
            itemID: itemID,
            fileName: "snapshot.html",
            contentType: "text/html"
        )
        let text = makeAttachment(
            itemID: itemID,
            fileName: "notes.txt",
            contentType: "text/plain"
        )
        let model = makeAppModel(providers: [NoopMetadataProvider()])

        model.reader.open(html)
        #expect(model.reader.activeAttachment == html)
        #expect(model.statusMessage == "Reading snapshot.html")

        model.reader.open(text)
        #expect(model.reader.activeAttachment == text)
        #expect(model.statusMessage == "Reading notes.txt")
    }

    @Test("selecting a different item clears active reader")
    func selectingDifferentItemClearsActiveReader() {
        let attachment = makeAttachment(
            itemID: UUID(),
            fileName: "reader.pdf",
            contentType: "application/pdf"
        )
        let model = makeAppModel(providers: [NoopMetadataProvider()])

        model.reader.open(attachment)
        model.selectItem(id: UUID())

        #expect(model.reader.activeAttachment == nil)
    }
}
