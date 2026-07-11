import AppKit
import CitrationCore
import SwiftUI
import WebKit

// MARK: - EPUBReaderView

struct EPUBReaderView: View {
    // MARK: Internal

    let attachment: LocalAttachment
    let progress: ReaderProgress?
    let annotations: [SynchronizedLibraryAnnotation]
    let state: EPUBReaderState
    let onProgressChange: (ReaderProgress) -> Void
    let onCreateAnnotation: (EPUBSelectionInfo, AnnotationColor, AnnotationKind) -> Void

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            controls
            Divider()
            content
            if let selection = state.selection {
                selectionBar(selection)
            }
        }
        .task(id: attachment.objectKey) {
            state.load(attachment: attachment, progress: progress)
        }
        .onChange(of: progress) { _, value in
            state.load(attachment: attachment, progress: value)
        }
    }

    // MARK: Private

    private var controls: some View {
        @Bindable var state = state

        return HStack(spacing: 8) {
            Button(action: state.goBackward) {
                Image(systemName: "chevron.left")
            }
            .disabled(!state.canGoBackward)
            .help("Previous section")

            Button(action: state.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!state.canGoForward)
            .help("Next section")

            Menu {
                if let publication = state.publication {
                    ForEach(publication.tableOfContents) { item in
                        Button(item.title) {
                            state.navigate(to: item.readingOrderIndex, fragment: item.fragment)
                        }
                    }
                }
            } label: {
                Label(state.currentItem?.title ?? "Contents", systemImage: "list.bullet")
                    .lineLimit(1)
            }
            .frame(maxWidth: 260)

            Spacer()

            TextField("Search book", text: $state.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(state.performSearch)
            Button(action: state.performSearch) {
                Image(systemName: "magnifyingglass")
            }
            .help("Search the entire book")

            if !state.searchResults.isEmpty {
                Menu("\(state.searchResults.count) Results") {
                    ForEach(state.searchResults) { result in
                        Button {
                            state.selectSearchResult(result)
                        } label: {
                            Text("\(result.chapterTitle): \(result.excerpt)")
                        }
                    }
                }
            }

            Button(action: state.decreaseFontSize) {
                Image(systemName: "textformat.size.smaller")
            }
            .help("Decrease text size")
            Button(action: state.increaseFontSize) {
                Image(systemName: "textformat.size.larger")
            }
            .help("Increase text size")

            Menu {
                ForEach(EPUBReaderTheme.allCases) { theme in
                    Button(theme.label) {
                        state.theme = theme
                    }
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled")
            }
            .help("Reading theme")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = state.errorMessage {
            ContentUnavailableView(
                "EPUB could not be opened",
                systemImage: "book.closed",
                description: Text(errorMessage)
            )
        } else if let publication = state.publication, let item = state.currentItem {
            EPUBWebView(
                publication: publication,
                item: item,
                readingOrderIndex: state.currentIndex,
                requestedCFI: state.requestedCFI,
                requestedFragment: state.requestedFragment,
                requestedSearchQuery: state.requestedSearchQuery,
                fontScale: state.fontScale,
                theme: state.theme,
                annotations: annotations,
                onNavigate: state.navigate,
                onProgress: persistProgress,
                onSelection: { state.selection = $0 }
            )
        } else {
            ProgressView("Opening EPUB…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectionBar(_ selection: EPUBSelectionInfo) -> some View {
        HStack {
            Text(selection.text)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Menu("Highlight") {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    Button(color.rawValue.capitalized) {
                        onCreateAnnotation(selection, color, .highlight)
                        state.selection = nil
                    }
                }
            }
            Button("Underline") {
                onCreateAnnotation(selection, .yellow, .underline)
                state.selection = nil
            }
        }
        .padding(10)
        .background(.bar)
    }

    private func persistProgress(cfi: String, chapterFraction: Double) {
        guard let publication = state.publication else {
            return
        }
        let overallFraction = (
            Double(state.currentIndex) + chapterFraction
        ) / Double(max(publication.readingOrder.count, 1))
        onProgressChange(
            ReaderProgress(
                itemID: attachment.itemID,
                attachmentKey: attachment.objectKey,
                location: .epubCFI(cfi),
                fractionComplete: overallFraction
            )
        )
    }
}

// MARK: - EPUBWebView

struct EPUBWebView: NSViewRepresentable {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        // MARK: Lifecycle

        init(parent: EPUBWebView) {
            self.parent = parent
        }

        // MARK: Internal

        var parent: EPUBWebView
        var loadedURL: URL?

        func load(item: EPUBSpineItem, publication: EPUBPublication, in webView: WKWebView) {
            loadedURL = item.documentURL
            isReady = false
            appliedSignature = nil
            webView.loadFileURL(item.documentURL, allowingReadAccessTo: publication.rootDirectory)
        }

        func applyState(to webView: WKWebView) {
            guard isReady else {
                return
            }
            let annotationPayload = annotationPayload()
            let signature = [
                String(parent.fontScale),
                parent.theme.rawValue,
                parent.requestedCFI ?? "",
                parent.requestedFragment ?? "",
                parent.requestedSearchQuery ?? "",
                annotationPayload,
            ].joined(separator: "|")
            guard signature != appliedSignature else {
                return
            }
            appliedSignature = signature

            let configuration: [String: Any] = [
                "base": parent.item.cfiBase,
                "spineIndex": parent.item.spineIndex,
                "fontScale": parent.fontScale,
                "theme": parent.theme.rawValue,
            ]
            evaluate("window.citrationEPUB?.configure(\(json(configuration)))", in: webView)
            evaluate("window.citrationEPUB?.renderAnnotations(\(annotationPayload))", in: webView)
            if let cfi = parent.requestedCFI {
                evaluate("window.citrationEPUB?.restore(\(json(cfi)))", in: webView)
            } else if let fragment = parent.requestedFragment {
                evaluate("window.citrationEPUB?.navigateFragment(\(json(fragment)))", in: webView)
            } else if let query = parent.requestedSearchQuery {
                evaluate("window.citrationEPUB?.find(\(json(query)))", in: webView)
            }
            evaluate("window.citrationEPUB?.reportProgress()", in: webView)
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            preferences.allowsContentJavaScript = false
            guard
                navigationAction.navigationType == .linkActivated,
                let destination = navigationAction.request.url
            else {
                decisionHandler(.allow, preferences)
                return
            }
            if
                let index = parent.publication.readingOrder.firstIndex(where: {
                    $0.documentURL.standardizedFileURL == destination.deletingFragment.standardizedFileURL
                })
            {
                parent.onNavigate(index, destination.fragment, nil)
            } else if !destination.isFileURL {
                NSWorkspace.shared.open(destination)
            }
            decisionHandler(.cancel, preferences)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            _ = userContentController
            guard
                let body = message.body as? [String: Any],
                let type = body["type"] as? String
            else {
                return
            }
            switch type {
            case "ready":
                isReady = true
                if let webView = message.webView {
                    applyState(to: webView)
                }

            case "progress":
                if let cfi = body["cfi"] as? String, let fraction = body["fraction"] as? Double {
                    parent.onProgress(cfi, fraction)
                }

            case "selection":
                guard let selection = body["selection"] as? [String: Any] else {
                    parent.onSelection(nil)
                    return
                }
                if
                    let text = selection["text"] as? String,
                    let position = selection["position"] as? String,
                    let sortIndex = selection["sortIndex"] as? String
                {
                    parent.onSelection(
                        EPUBSelectionInfo(text: text, positionJSON: position, sortIndex: sortIndex)
                    )
                }

            default:
                break
            }
        }

        // MARK: Private

        private var isReady = false
        private var appliedSignature: String?

        private func annotationPayload() -> String {
            let values: [[String: String]] = parent.annotations.compactMap { annotation in
                guard
                    annotation.kind == .highlight || annotation.kind == .underline,
                    case let .epubCFI(cfi) = annotation.location,
                    parent.publication.readingOrderIndex(forCFI: cfi) == parent.readingOrderIndex
                else {
                    return nil
                }
                return [
                    "cfi": cfi,
                    "kind": annotation.type,
                    "color": annotation.color,
                ]
            }
            return json(values)
        }

        private func evaluate(_ source: String, in webView: WKWebView) {
            webView.evaluateJavaScript(source, in: nil, in: .page) { _ in }
        }

        private func json(_ value: Any) -> String {
            guard
                JSONSerialization.isValidJSONObject(value),
                let data = try? JSONSerialization.data(withJSONObject: value),
                let string = String(data: data, encoding: .utf8)
            else {
                return "null"
            }
            return string
        }
    }

    let publication: EPUBPublication
    let item: EPUBSpineItem
    let readingOrderIndex: Int
    let requestedCFI: String?
    let requestedFragment: String?
    let requestedSearchQuery: String?
    let fontScale: Double
    let theme: EPUBReaderTheme
    let annotations: [SynchronizedLibraryAnnotation]
    let onNavigate: (Int, String?, String?) -> Void
    let onProgress: (String, Double) -> Void
    let onSelection: (EPUBSelectionInfo?) -> Void

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "citrationEPUB")
        webView.stopLoading()
        coordinator.loadedURL = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "citrationEPUB")
        contentController.addUserScript(
            WKUserScript(
                source: EPUBReaderScript.source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(item: item, publication: publication, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedURL != item.documentURL {
            context.coordinator.load(item: item, publication: publication, in: webView)
        } else {
            context.coordinator.applyState(to: webView)
        }
    }
}

private extension URL {
    var deletingFragment: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.fragment = nil
        return components.url ?? self
    }
}
