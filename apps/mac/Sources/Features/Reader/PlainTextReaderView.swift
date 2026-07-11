import AppKit
import CitrationCore
import Foundation
import SwiftUI

// MARK: - PlainTextReaderView

struct PlainTextReaderView: NSViewRepresentable {
    // MARK: Internal

    final class Coordinator {
        var loadedURL: URL?
    }

    let attachment: LocalAttachment
    let progress: ReaderProgress?
    let onProgressChange: (ReaderProgress) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        loadDocument(in: textView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard
            context.coordinator.loadedURL != attachment.localURL,
            let textView = scrollView.documentView as? NSTextView
        else {
            return
        }
        loadDocument(in: textView, context: context)
    }

    // MARK: Private

    private func loadDocument(in textView: NSTextView, context: Context) {
        context.coordinator.loadedURL = attachment.localURL
        do {
            textView.string = try CachedPlainTextDocument(fileURL: attachment.localURL).text
            textView.textColor = .labelColor
            reportInitialProgressIfNeeded()
        } catch {
            textView.string = "Text document could not be opened.\n\n\(error.localizedDescription)"
            textView.textColor = .secondaryLabelColor
        }
    }

    private func reportInitialProgressIfNeeded() {
        guard progress == nil else {
            return
        }
        onProgressChange(
            ReaderProgress(
                itemID: attachment.itemID,
                attachmentKey: attachment.objectKey,
                location: .textOffset(0),
                fractionComplete: 0
            )
        )
    }
}
