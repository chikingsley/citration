import AppKit
import CitrationCore
import Foundation
import SwiftUI
import WebKit

// MARK: - CachedHTMLDocument

struct CachedHTMLDocument: Equatable {
    // MARK: Lifecycle

    init(fileURL: URL) throws {
        var encoding: UInt = 0
        let source = try NSString(contentsOf: fileURL, usedEncoding: &encoding) as String
        html = Self.injectContentSecurityPolicy(into: source)
        baseURL = fileURL.deletingLastPathComponent()
    }

    // MARK: Internal

    static let contentSecurityPolicy = """
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; \
    img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; \
    media-src 'self' data:; object-src 'none'; frame-src 'none'; connect-src 'none'">
    """

    let html: String
    let baseURL: URL

    // MARK: Private

    private static func injectContentSecurityPolicy(into source: String) -> String {
        if let openingHeadEnd = endOfOpeningTag(named: "head", in: source) {
            var result = source
            result.insert(contentsOf: contentSecurityPolicy, at: openingHeadEnd)
            return result
        }
        if let openingHTMLEnd = endOfOpeningTag(named: "html", in: source) {
            var result = source
            result.insert(contentsOf: "<head>\(contentSecurityPolicy)</head>", at: openingHTMLEnd)
            return result
        }
        return "<!doctype html><html><head>\(contentSecurityPolicy)</head><body>\(source)</body></html>"
    }

    private static func endOfOpeningTag(named name: String, in source: String) -> String.Index? {
        var searchRange = source.startIndex ..< source.endIndex
        while
            let tagStart = source.range(
                of: "<\(name)",
                options: .caseInsensitive,
                range: searchRange
            )
        {
            let boundary = tagStart.upperBound
            let isExactTag = boundary == source.endIndex
                || source[boundary] == ">"
                || source[boundary] == "/"
                || source[boundary].isWhitespace
            if
                isExactTag,
                let tagEnd = source[tagStart.lowerBound...].firstIndex(of: ">")
            {
                return source.index(after: tagEnd)
            }
            searchRange = boundary ..< source.endIndex
        }
        return nil
    }
}

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
