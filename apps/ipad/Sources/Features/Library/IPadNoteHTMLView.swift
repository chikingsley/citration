import SwiftUI
import UIKit
import WebKit

/// Renders Zotero note HTML without persistent web state or document scripts.
struct IPadNoteHTMLView: UIViewRepresentable {
    // MARK: Internal

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }

    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.accessibilityLabel = "Zotero note"
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else {
            return
        }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(Self.document(html), baseURL: nil)
    }

    // MARK: Private

    private static func document(_ body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy"
              content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>
        :root { color-scheme: light dark; }
        body {
          margin: 0;
          font: -apple-system-body;
          color: CanvasText;
          background: transparent;
          overflow-wrap: anywhere;
        }
        img { max-width: 100%; height: auto; }
        a { color: LinkText; }
        </style>
        </head>
        <body><main>\(body)</main></body>
        </html>
        """
    }
}
