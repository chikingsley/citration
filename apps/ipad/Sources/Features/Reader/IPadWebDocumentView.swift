import CitrationCore
import SwiftUI
import UIKit
import WebKit

struct IPadWebDocumentView: UIViewRepresentable {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
        // MARK: Lifecycle

        init(parent: IPadWebDocumentView) {
            self.parent = parent
        }

        // MARK: Internal

        var parent: IPadWebDocumentView
        var loadedURL: URL?
        var didRestoreProgress = false
        var isRestoring = false
        var progressTask: Task<Void, Never>?

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                if destination.scheme == "https" || destination.scheme == "http" {
                    UIApplication.shared.open(destination)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(destination.isFileURL || destination.scheme == "about" ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation?) {
            restoreProgress(in: webView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard loadedURL != nil, didRestoreProgress, !isRestoring else {
                return
            }
            progressTask?.cancel()
            progressTask = Task { [weak self, weak scrollView] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, let scrollView else {
                    return
                }
                let maximumOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
                let fraction = maximumOffset > 0 ? min(max(scrollView.contentOffset.y / maximumOffset, 0), 1) : 0
                parent.onProgress(Int(fraction * 1_000_000), fraction)
            }
        }

        // MARK: Private

        private func restoreProgress(in webView: WKWebView) {
            guard !didRestoreProgress else {
                return
            }
            didRestoreProgress = true
            webView.layoutIfNeeded()
            let maximumOffset = max(webView.scrollView.contentSize.height - webView.scrollView.bounds.height, 0)
            isRestoring = true
            webView.scrollView.setContentOffset(
                CGPoint(x: 0, y: maximumOffset * CGFloat(parent.progress?.fractionComplete ?? 0)),
                animated: false
            )
            isRestoring = false
        }
    }

    let url: URL
    let format: DocumentFormat
    let progress: ReaderProgress?
    let onProgress: (Int, Double) -> Void

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.progressTask?.cancel()
        webView.scrollView.delegate = nil
        webView.navigationDelegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loadedURL != url else {
            return
        }
        context.coordinator.loadedURL = url
        context.coordinator.didRestoreProgress = false
        switch format {
        case .html:
            do {
                let document = try CachedHTMLDocument(fileURL: url)
                webView.loadHTMLString(document.html, baseURL: document.baseURL)
            } catch {
                let message = error.localizedDescription
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                webView.loadHTMLString("<h1>HTML snapshot could not be opened</h1><p>\(message)</p>", baseURL: nil)
            }

        case .epub:
            webView.loadHTMLString(
                "<main><h1>EPUB reader</h1><p>The sandbox-safe EPUB package reader is being installed.</p></main>",
                baseURL: nil
            )

        default:
            break
        }
    }
}
