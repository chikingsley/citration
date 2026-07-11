import CitrationCore
import SwiftUI
import UIKit
import WebKit

// MARK: - IPadEPUBReaderView

struct IPadEPUBReaderView: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    let item: SynchronizedLibraryItem
    let record: ZoteroAttachmentCacheRecord
    let url: URL

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
        .navigationTitle(record.filename)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: record.itemKey) {
            await model.openReader(item: item, record: record)
            state.load(attachment: attachment, progress: model.readerProgress)
        }
        .onChange(of: model.readerProgress) { _, progress in
            state.load(attachment: attachment, progress: progress)
        }
        .onDisappear {
            state.reset()
        }
    }

    // MARK: Private

    @State private var state: EPUBReaderState = .init()

    private var attachment: LibraryAttachment {
        LibraryAttachment(
            itemID: item.identity.appUUID,
            fileName: record.filename,
            objectKey: record.itemKey,
            localURL: url,
            contentType: record.contentType,
            size: 0,
            createdAt: .distantPast
        )
    }

    private var controls: some View {
        @Bindable var state = state

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button("Previous", systemImage: "chevron.left", action: state.goBackward)
                    .disabled(!state.canGoBackward)
                Button("Next", systemImage: "chevron.right", action: state.goForward)
                    .disabled(!state.canGoForward)
                Menu {
                    if let publication = state.publication {
                        ForEach(publication.tableOfContents) { entry in
                            Button(entry.title) {
                                state.navigate(to: entry.readingOrderIndex, fragment: entry.fragment)
                            }
                        }
                    }
                } label: {
                    Label(state.currentItem?.title ?? "Contents", systemImage: "list.bullet")
                        .lineLimit(1)
                }
                TextField("Search book", text: $state.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(state.performSearch)
                Button("Search", systemImage: "magnifyingglass", action: state.performSearch)
                if !state.searchResults.isEmpty {
                    Menu("\(state.searchResults.count) Results") {
                        ForEach(state.searchResults) { result in
                            Button("\(result.chapterTitle): \(result.excerpt)") {
                                state.selectSearchResult(result)
                            }
                        }
                    }
                }
                Button("Smaller Text", systemImage: "textformat.size.smaller", action: state.decreaseFontSize)
                Button("Larger Text", systemImage: "textformat.size.larger", action: state.increaseFontSize)
                Menu {
                    ForEach(EPUBReaderTheme.allCases) { theme in
                        Button(theme.label) { state.theme = theme }
                    }
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
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
        } else if let publication = state.publication, let currentItem = state.currentItem {
            IPadEPUBWebView(
                publication: publication,
                item: currentItem,
                readingOrderIndex: state.currentIndex,
                requestedCFI: state.requestedCFI,
                requestedFragment: state.requestedFragment,
                requestedSearchQuery: state.requestedSearchQuery,
                fontScale: state.fontScale,
                theme: state.theme,
                annotations: model.readerAnnotations,
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
                        create(selection: selection, kind: .highlight, color: color)
                    }
                }
            }
            Button("Underline") {
                create(selection: selection, kind: .underline, color: .yellow)
            }
        }
        .padding(10)
        .background(.bar)
    }

    private func create(selection: EPUBSelectionInfo, kind: AnnotationKind, color: AnnotationColor) {
        state.selection = nil
        Task {
            await model.createEPUBAnnotation(
                item: item,
                record: record,
                selection: selection,
                kind: kind,
                color: color
            )
        }
    }

    private func persistProgress(cfi: String, chapterFraction: Double) {
        guard let publication = state.publication else {
            return
        }
        let fraction = (Double(state.currentIndex) + chapterFraction)
            / Double(max(publication.readingOrder.count, 1))
        model.updateEPUBProgress(
            item: item,
            record: record,
            cfi: cfi,
            fractionComplete: fraction
        )
    }
}

// MARK: - IPadEPUBWebView

private struct IPadEPUBWebView: UIViewRepresentable {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        // MARK: Lifecycle

        init(parent: IPadEPUBWebView) {
            self.parent = parent
        }

        // MARK: Internal

        var parent: IPadEPUBWebView
        var loadedURL: URL?
        var isReady = false
        var appliedSignature: String?

        func load(in webView: WKWebView) {
            loadedURL = parent.item.documentURL
            isReady = false
            appliedSignature = nil
            webView.loadFileURL(parent.item.documentURL, allowingReadAccessTo: parent.publication.rootDirectory)
        }

        func applyState(to webView: WKWebView) {
            guard isReady else {
                return
            }
            let annotationPayload = json(parent.annotations.compactMap { annotation -> [String: String]? in
                guard
                    annotation.kind == .highlight || annotation.kind == .underline,
                    case let .epubCFI(cfi) = annotation.location,
                    parent.publication.readingOrderIndex(forCFI: cfi) == parent.readingOrderIndex
                else {
                    return nil
                }
                return ["cfi": cfi, "kind": annotation.type, "color": annotation.color]
            })
            let signature = [
                String(parent.fontScale), parent.theme.rawValue,
                parent.requestedCFI ?? "", parent.requestedFragment ?? "",
                parent.requestedSearchQuery ?? "", annotationPayload,
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
                UIApplication.shared.open(destination)
            }
            decisionHandler(.cancel, preferences)
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
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
                guard
                    let selection = body["selection"] as? [String: Any],
                    let text = selection["text"] as? String,
                    let position = selection["position"] as? String,
                    let sortIndex = selection["sortIndex"] as? String
                else {
                    parent.onSelection(nil)
                    return
                }
                parent.onSelection(EPUBSelectionInfo(text: text, positionJSON: position, sortIndex: sortIndex))

            default:
                break
            }
        }

        // MARK: Private

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

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "citrationEPUB")
        webView.stopLoading()
        coordinator.loadedURL = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "citrationEPUB")
        contentController.addUserScript(WKUserScript(
            source: EPUBReaderScript.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedURL != item.documentURL {
            context.coordinator.load(in: webView)
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
