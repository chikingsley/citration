import AppKit
import CitrationCore
import Foundation
import SwiftUI
import WebKit

// MARK: - HTMLSnapshotReaderView

struct HTMLSnapshotReaderView: NSViewRepresentable {
    // MARK: Internal

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            if
                let url = navigationAction.request.url,
                ["http", "https"].contains(url.scheme?.lowercased())
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    let attachment: LocalAttachment
    let progress: ReaderProgress?
    let onProgressChange: (ReaderProgress) -> Void

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return configuration
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = .clear
        loadDocument(in: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != attachment.localURL else {
            return
        }
        loadDocument(in: webView, context: context)
    }

    // MARK: Private

    private static func errorHTML(message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<h1>HTML snapshot could not be opened</h1><p>\(escaped)</p>"
    }

    private func loadDocument(in webView: WKWebView, context: Context) {
        context.coordinator.loadedURL = attachment.localURL
        do {
            let document = try CachedHTMLDocument(fileURL: attachment.localURL)
            webView.loadHTMLString(document.html, baseURL: document.baseURL)
            reportInitialProgressIfNeeded()
        } catch {
            webView.loadHTMLString(Self.errorHTML(message: error.localizedDescription), baseURL: nil)
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
