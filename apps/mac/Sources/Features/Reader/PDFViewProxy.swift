import Foundation
import Observation
import PDFKit

// MARK: - PDFViewProxy

/// Bridges SwiftUI reader actions to PDFView and streams search matches
/// through main-queue PDFKit notifications.
@Observable
@MainActor
final class PDFViewProxy: NSObject {
    // MARK: Internal

    weak var pdfView: PDFView?
    private(set) var currentPageNumber = 0
    private(set) var pageCount = 0
    private(set) var searchResults: [PDFSelection] = []
    private(set) var currentSearchResult = 0
    private(set) var isSearching = false

    var canGoBackward: Bool {
        currentPageNumber > 1
    }

    var canGoForward: Bool {
        currentPageNumber > 0 && currentPageNumber < pageCount
    }

    func goBackward() {
        pdfView?.goToPreviousPage(nil)
        updatePageStatus()
    }

    func goForward() {
        pdfView?.goToNextPage(nil)
        updatePageStatus()
    }

    func zoomOut() {
        pdfView?.zoomOut(nil)
    }

    func zoomIn() {
        pdfView?.zoomIn(nil)
    }

    func fitPage() {
        guard let pdfView else {
            return
        }
        pdfView.autoScales = true
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
    }

    func setLayout(mode: PDFDisplayMode, direction: PDFDisplayDirection) {
        pdfView?.displayMode = mode
        pdfView?.displayDirection = direction
        fitPage()
    }

    func find(_ query: String) {
        guard let document = pdfView?.document else {
            return
        }
        searchFallbackTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        document.cancelFindString()
        searchResults = []
        currentSearchResult = 0
        isSearching = true
        document.beginFindString(query, withOptions: .caseInsensitive)
        let documentBox = PDFDocumentBox(document)
        searchFallbackTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard let self, searchGeneration == generation, searchResults.isEmpty, isSearching else {
                return
            }
            document.cancelFindString()
            let boxedMatches = await Task.detached {
                PDFSelectionArrayBox(documentBox.value.findString(query, withOptions: .caseInsensitive))
            }.value
            let matches = boxedMatches.value
            guard searchGeneration == generation else {
                return
            }
            searchResults = matches
            currentSearchResult = 0
            isSearching = false
            if !matches.isEmpty {
                showCurrentSearchResult()
            }
        }
    }

    func observeSearchNotifications(for document: PDFDocument) {
        let center = NotificationCenter.default
        searchNotificationTokens.forEach(center.removeObserver)
        searchNotificationTokens = [
            center.addObserver(forName: .PDFDocumentDidFindMatch, object: document, queue: .main) {
                [weak self] notification in
                guard let selection = notification.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection else {
                    return
                }
                let boxedSelection = PDFSelectionBox(selection)
                MainActor.assumeIsolated { self?.recordSearchMatch(boxedSelection.value) }
            },
            center.addObserver(forName: .PDFDocumentDidEndFind, object: document, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isSearching = false }
            },
        ]
    }

    func findNext() {
        guard !searchResults.isEmpty else {
            return
        }
        currentSearchResult = (currentSearchResult + 1) % searchResults.count
        showCurrentSearchResult()
    }

    func findPrevious() {
        guard !searchResults.isEmpty else {
            return
        }
        currentSearchResult = (currentSearchResult - 1 + searchResults.count) % searchResults.count
        showCurrentSearchResult()
    }

    func updatePageStatus() {
        guard let document = pdfView?.document, let page = pdfView?.currentPage else {
            currentPageNumber = 0
            pageCount = pdfView?.document?.pageCount ?? 0
            return
        }
        let index = document.index(for: page)
        currentPageNumber = index == NSNotFound ? 0 : index + 1
        pageCount = document.pageCount
    }

    func selectionInfo() -> PDFSelectionInfo? {
        guard
            let pdfView,
            let selection = pdfView.currentSelection,
            let text = selection.string?.bcTrimmedNonEmpty,
            let page = selection.pages.first,
            let document = pdfView.document
        else {
            return nil
        }

        let index = document.index(for: page)
        let selectedPages = selection.pages
        guard index != NSNotFound, selectedPages.count <= 2 else {
            return nil
        }
        let selectionsByLine = selection.selectionsByLine()
        let primaryRects = selectionsByLine.compactMap { line -> CGRect? in
            guard line.pages.contains(page) else {
                return nil
            }
            let bounds = line.bounds(for: page)
            return bounds.isEmpty ? nil : bounds
        }
        let nextPageRects: [CGRect] = if selectedPages.count == 2 {
            selectionsByLine.compactMap { line -> CGRect? in
                let nextPage = selectedPages[1]
                guard line.pages.contains(nextPage) else {
                    return nil
                }
                let bounds = line.bounds(for: nextPage)
                return bounds.isEmpty ? nil : bounds
            }
        } else {
            []
        }
        guard
            let anchor = PDFAnnotationAnchor.make(
                page: page,
                pageIndex: index,
                primaryRects: primaryRects,
                nextPageRects: nextPageRects
            )
        else {
            return nil
        }
        return PDFSelectionInfo(text: text, anchor: anchor)
    }

    // MARK: Private

    private var searchNotificationTokens: [NSObjectProtocol] = []
    private var searchFallbackTask: Task<Void, Never>?
    private var searchGeneration = 0

    private func recordSearchMatch(_ instance: PDFSelection) {
        searchFallbackTask?.cancel()
        searchResults.append(instance)
        if searchResults.count == 1 {
            showCurrentSearchResult()
        }
    }

    private func showCurrentSearchResult() {
        guard searchResults.indices.contains(currentSearchResult) else {
            return
        }
        let selection = searchResults[currentSearchResult]
        pdfView?.setCurrentSelection(selection, animate: true)
        pdfView?.go(to: selection)
        updatePageStatus()
    }
}

// MARK: - PDFSelectionBox

private struct PDFSelectionBox: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ value: PDFSelection) {
        self.value = value
    }

    // MARK: Internal

    let value: PDFSelection
}

// MARK: - PDFDocumentBox

private struct PDFDocumentBox: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ value: PDFDocument) {
        self.value = value
    }

    // MARK: Internal

    let value: PDFDocument
}

// MARK: - PDFSelectionArrayBox

private struct PDFSelectionArrayBox: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ value: [PDFSelection]) {
        self.value = value
    }

    // MARK: Internal

    let value: [PDFSelection]
}
