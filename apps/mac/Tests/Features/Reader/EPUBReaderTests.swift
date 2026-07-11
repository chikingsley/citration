import AppKit
@testable import Citration
import CitrationCore
import Foundation
import SwiftUI
import Testing
import WebKit

@Suite("EPUB reader")
@MainActor
struct EPUBReaderTests {
    // MARK: Internal

    @Test("real publication restores a portable CFI to its original spine section")
    func realPublicationRestoresPortableCFI() {
        let itemID = UUID()
        let attachment = LocalAttachment(
            itemID: itemID,
            fileName: "language-learning-theories.epub",
            objectKey: "EPUBTEST",
            localURL: realDocumentFixture("language-learning-theories.epub"),
            contentType: "application/epub+zip",
            size: 4_121_713,
            createdAt: .now
        )
        let cfi = "epubcfi(/6/24!/4/2/2/1:0)"
        let progress = ReaderProgress(
            itemID: itemID,
            attachmentKey: attachment.objectKey,
            location: .epubCFI(cfi),
            fractionComplete: 0.4
        )
        let state = EPUBReaderState()

        state.load(attachment: attachment, progress: progress)

        #expect(state.publication?.readingOrder.count == 24)
        #expect(state.currentItem?.spineIndex == 11)
        #expect(state.currentItem?.cfiBase == "/6/24")
        #expect(state.requestedCFI == cfi)
        state.reset()
    }

    @Test("real EPUB selection persists as an exact synchronized FragmentSelector")
    func realEPUBSelectionPersistsAsFragmentSelector() async throws {
        let item = BCItem(title: "Language Learning Theories")
        let model = makeAppModel(initialItems: [item])
        await model.refreshItems()
        model.selectItem(id: item.id)
        model.importer.importAttachments(
            urls: [realDocumentFixture("language-learning-theories.epub")],
            mode: .attachToSelectedItem
        )
        try await waitUntil(timeout: 4) {
            model.importer.selectedItemAttachments.count == 1 && !model.importer.isImporting
        }
        let attachment = try #require(model.importer.selectedItemAttachments.first)
        let cfi = "epubcfi(/6/24!/4/2/2,/1:0,/1:8)"
        let positionJSON = """
        {"type":"FragmentSelector","conformsTo":"http://www.idpf.org/epub/linking/cfi/epub-cfi.html","value":"\(cfi)"}
        """
        let selection = EPUBSelectionInfo(
            text: "Language",
            positionJSON: positionJSON,
            sortIndex: "00011|00000000"
        )

        model.reader.open(attachment)
        model.reader.addEPUBAnnotation(selection: selection, color: .green, kind: .highlight)
        try await waitUntil { model.reader.annotations.count == 1 }

        let annotation = try #require(model.reader.annotations.first)
        #expect(annotation.location == .epubCFI(cfi))
        #expect(annotation.positionJSON == positionJSON)
        #expect(annotation.text == "Language")
        #expect(annotation.sortIndex == "00011|00000000")
        #expect(annotation.syncState == .dirty)
        #expect(model.statusMessage == "Added EPUB highlight")
        let libraryID = try #require(model.observedLibraryID)
        let object = try #require(try model.database.fetchObject(
            libraryID: libraryID,
            kind: .item,
            key: annotation.identity.objectKey
        ))
        let storedData = try #require(object.current.objectValue?["data"]?.objectValue)
        #expect(storedData["annotationPosition"]?.stringValue == positionJSON)
        #expect(storedData["annotationText"]?.stringValue == "Language")
    }

    @Test("authored EPUB scripts stay disabled while the reader bridge executes")
    func authoredScriptsStayDisabled() async throws {
        let publication = try EPUBPackageReader().publication(
            from: realDocumentFixture("language-learning-theories.epub")
        )
        defer { try? FileManager.default.removeItem(at: publication.rootDirectory) }
        let item = try #require(publication.readingOrder.first)
        let originalMarkup = try String(contentsOf: item.documentURL, encoding: .utf8)
        var markup = originalMarkup
        markup = markup.replacingOccurrences(
            of: "</body>",
            with: "<script>window.__citrationAuthoredScriptRan = true;</script></body>"
        )
        #expect(markup != originalMarkup)
        try markup.write(to: item.documentURL, atomically: true, encoding: .utf8)

        let readerView = EPUBWebView(
            publication: publication,
            item: item,
            readingOrderIndex: 0,
            requestedCFI: nil,
            requestedFragment: nil,
            requestedSearchQuery: nil,
            fontScale: 1,
            theme: .light,
            annotations: [],
            onNavigate: { _, _, _ in },
            onProgress: { _, _ in },
            onSelection: { _ in }
        )
        let hostingView = NSHostingView(rootView: readerView.frame(width: 800, height: 600))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        try await Task.sleep(for: .seconds(1))
        let webView = try #require(firstSubview(of: WKWebView.self, in: hostingView))
        let result = try await webView.evaluateJavaScript(
            "[window.__citrationEPUBInstalled === true, window.__citrationAuthoredScriptRan === true]"
        ) as? [Bool]

        #expect(result == [true, false])
    }

    // MARK: Private

    private func firstSubview<View: NSView>(of type: View.Type, in root: NSView) -> View? {
        if let match = root as? View {
            return match
        }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
