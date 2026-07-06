@testable import Citration
import CitrationCore
import Foundation
import Testing

@Suite("AppModel reader")
@MainActor
struct AppModelReaderTests {
    @Test("opening PDF reader tracks attachment and selected item")
    func openingPDFReaderTracksAttachmentAndSelectedItem() {
        let itemID = UUID()
        let attachment = makeAttachment(
            itemID: itemID,
            fileName: "reader.pdf",
            contentType: "application/pdf"
        )
        let model = makeAppModel(providers: [NoopMetadataProvider()])

        model.reader.open(attachment)

        #expect(model.reader.activeAttachment == attachment)
        #expect(model.selectedItemID == itemID)
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
