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
