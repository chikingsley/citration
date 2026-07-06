import AppKit
import CitrationCore
import SwiftUI
import WebKit

// MARK: - EPUBReaderView

struct EPUBReaderView: NSViewRepresentable {
    // MARK: Internal

    final class Coordinator: NSObject {
        // MARK: Lifecycle

        deinit {
            removePublicationRoot()
        }

        // MARK: Internal

        var loadedObjectKey: String?
        var publicationRoot: URL?

        func removePublicationRoot() {
            if let publicationRoot {
                try? FileManager.default.removeItem(at: publicationRoot)
            }
            publicationRoot = nil
        }
    }

    let attachment: LocalAttachment
    let progress: ReaderProgress?
    let onProgressChange: (ReaderProgress) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        loadPublication(in: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedObjectKey != attachment.objectKey else {
            return
        }
        loadPublication(in: webView, context: context)
    }

    // MARK: Private

    private static func errorHTML(message: String) -> String {
        let escapedMessage = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {
              font: -apple-system-body;
              margin: 32px;
              color: #222;
              background: #fff;
            }
          </style>
        </head>
        <body>
          <h1>EPUB could not be opened</h1>
          <p>\(escapedMessage)</p>
        </body>
        </html>
        """
    }

    private func loadPublication(in webView: WKWebView, context: Context) {
        var didLoadPublication = false
        do {
            let publication = try EPUBPackageReader().publication(from: attachment.localURL)
            context.coordinator.removePublicationRoot()
            context.coordinator.loadedObjectKey = attachment.objectKey
            context.coordinator.publicationRoot = publication.rootDirectory
            webView.loadFileURL(
                publication.initialDocumentURL,
                allowingReadAccessTo: publication.rootDirectory
            )
            didLoadPublication = true
        } catch {
            context.coordinator.removePublicationRoot()
            context.coordinator.loadedObjectKey = attachment.objectKey
            webView.loadHTMLString(
                Self.errorHTML(message: error.localizedDescription),
                baseURL: nil
            )
        }

        if didLoadPublication, progress == nil {
            onProgressChange(
                ReaderProgress(
                    itemID: attachment.itemID,
                    attachmentKey: attachment.objectKey,
                    location: .epubCFI("epub-start"),
                    fractionComplete: nil
                )
            )
        }
    }
}
