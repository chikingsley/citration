import AppKit
import SwiftUI
import WebKit

struct NoteHTMLView: NSViewRepresentable {
    // MARK: Internal

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

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
            }
            decisionHandler(.cancel)
        }
    }

    let html: String

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return configuration
    }

    static func document(containing html: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta http-equiv="Content-Security-Policy"
                content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
          <style>
            :root { color-scheme: light dark; }
            body {
              margin: 8px 4px;
              font: -apple-system-body;
              color: -apple-system-label;
              background: transparent;
              overflow-wrap: anywhere;
            }
            a { color: -apple-system-link; }
            img { max-width: 100%; height: auto; }
            p:first-child { margin-top: 0; }
            p:last-child { margin-bottom: 0; }
          </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        load(html, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else {
            return
        }
        load(html, in: webView, coordinator: context.coordinator)
    }

    // MARK: Private

    private func load(_ html: String, in webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedHTML = html
        webView.loadHTMLString(Self.document(containing: html), baseURL: nil)
    }
}
