import CitrationCore
import Foundation
import Observation

// MARK: - EPUBReaderTheme

enum EPUBReaderTheme: String, CaseIterable, Identifiable {
    case light
    case sepia
    case dark

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        rawValue.capitalized
    }
}

// MARK: - EPUBSelectionInfo

struct EPUBSelectionInfo: Equatable {
    var text: String
    var positionJSON: String
    var sortIndex: String
}

// MARK: - EPUBReaderState

@MainActor
@Observable
final class EPUBReaderState {
    // MARK: Internal

    var publication: EPUBPublication?
    var currentIndex = 0
    var fontScale = 1.0
    var theme: EPUBReaderTheme = .light
    var searchText = ""
    var searchResults: [EPUBSearchResult] = []
    var selection: EPUBSelectionInfo?
    var requestedCFI: String?
    var requestedFragment: String?
    var requestedSearchQuery: String?
    var errorMessage: String?

    var currentItem: EPUBSpineItem? {
        guard let publication, publication.readingOrder.indices.contains(currentIndex) else {
            return nil
        }
        return publication.readingOrder[currentIndex]
    }

    var canGoBackward: Bool {
        currentIndex > 0
    }

    var canGoForward: Bool {
        guard let publication else {
            return false
        }
        return currentIndex + 1 < publication.readingOrder.count
    }

    func load(attachment: LibraryAttachment, progress: ReaderProgress?) {
        if loadedAttachmentKey == attachment.objectKey {
            restore(progress)
            return
        }
        reset()
        loadedAttachmentKey = attachment.objectKey
        do {
            let publication = try EPUBPackageReader().publication(from: attachment.localURL)
            self.publication = publication
            restore(progress)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        if let rootDirectory = publication?.rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        publication = nil
        currentIndex = 0
        searchText = ""
        searchResults = []
        selection = nil
        requestedCFI = nil
        requestedFragment = nil
        requestedSearchQuery = nil
        errorMessage = nil
        loadedAttachmentKey = nil
    }

    func goBackward() {
        navigate(to: currentIndex - 1)
    }

    func goForward() {
        navigate(to: currentIndex + 1)
    }

    func navigate(to index: Int, fragment: String? = nil, searchQuery: String? = nil) {
        guard let publication, publication.readingOrder.indices.contains(index) else {
            return
        }
        currentIndex = index
        requestedCFI = nil
        requestedFragment = fragment
        requestedSearchQuery = searchQuery
        selection = nil
    }

    @discardableResult
    func navigate(toCFI cfi: String) -> Bool {
        guard
            let publication,
            let index = publication.readingOrderIndex(forCFI: cfi)
        else {
            return false
        }
        currentIndex = index
        requestedCFI = cfi
        requestedFragment = nil
        requestedSearchQuery = nil
        selection = nil
        return true
    }

    func performSearch() {
        searchResults = publication?.search(searchText) ?? []
    }

    func selectSearchResult(_ result: EPUBSearchResult) {
        navigate(to: result.readingOrderIndex, searchQuery: result.query)
    }

    func increaseFontSize() {
        fontScale = min(fontScale + 0.1, 2.0)
    }

    func decreaseFontSize() {
        fontScale = max(fontScale - 0.1, 0.7)
    }

    // MARK: Private

    private var loadedAttachmentKey: String?

    private func restore(_ progress: ReaderProgress?) {
        guard
            let publication,
            case let .epubCFI(cfi) = progress?.location,
            let index = publication.readingOrderIndex(forCFI: cfi)
        else {
            return
        }
        currentIndex = index
        requestedCFI = cfi
    }
}
