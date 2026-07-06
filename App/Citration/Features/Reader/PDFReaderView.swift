import AppKit
import CitrationCore
import PDFKit
import SwiftUI

// MARK: - PDFReaderView

struct PDFReaderView: NSViewRepresentable {
    // MARK: Internal

    final class Coordinator: NSObject {
        var loadedURL: URL?
        var attachment: LocalAttachment?
        var onProgressChange: ((ReaderProgress) -> Void)?
        var appliedProgressToken: String?
        var isRestoringProgress = false
        var appliedAnnotationsToken: String?
        var renderedAnnotations: [PDFAnnotation] = []

        func configure(
            attachment: LocalAttachment,
            onProgressChange: @escaping (ReaderProgress) -> Void
        ) {
            self.attachment = attachment
            self.onProgressChange = onProgressChange
        }

        @MainActor
        @objc
        func pageChanged(_ notification: Notification) {
            guard
                !isRestoringProgress,
                let pdfView = notification.object as? PDFView,
                let document = pdfView.document,
                document.pageCount > 0,
                let page = pdfView.currentPage,
                let attachment
            else {
                return
            }

            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else {
                return
            }

            onProgressChange?(
                ReaderProgress(
                    itemID: attachment.itemID,
                    attachmentKey: attachment.objectKey,
                    location: .page(pageIndex + 1),
                    fractionComplete: Double(pageIndex + 1) / Double(document.pageCount)
                )
            )
        }
    }

    let attachment: LocalAttachment
    let progress: ReaderProgress?
    let annotations: [LibraryAnnotation]
    let proxy: PDFViewProxy
    let onProgressChange: (ReaderProgress) -> Void

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewPageChanged,
            object: nsView
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        proxy.pdfView = pdfView
        context.coordinator.configure(attachment: attachment, onProgressChange: onProgressChange)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .windowBackgroundColor
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        loadDocument(in: pdfView, context: context)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        proxy.pdfView = pdfView
        context.coordinator.configure(attachment: attachment, onProgressChange: onProgressChange)
        guard context.coordinator.loadedURL != attachment.localURL else {
            applyProgressIfNeeded(in: pdfView, context: context)
            applyAnnotationsIfNeeded(in: pdfView, context: context)
            return
        }
        loadDocument(in: pdfView, context: context)
    }

    // MARK: Private

    private func loadDocument(in pdfView: PDFView, context: Context) {
        pdfView.document = PDFDocument(url: attachment.localURL)
        context.coordinator.loadedURL = attachment.localURL
        context.coordinator.appliedProgressToken = nil
        pdfView.autoScales = true
        applyProgressIfNeeded(in: pdfView, context: context)
        applyAnnotationsIfNeeded(in: pdfView, context: context)
    }

    private func applyProgressIfNeeded(in pdfView: PDFView, context: Context) {
        guard
            let progress,
            progress.attachmentKey == attachment.objectKey,
            context.coordinator.appliedProgressToken != token(for: progress),
            case let .page(pageNumber) = progress.location,
            let document = pdfView.document,
            document.pageCount > 0
        else {
            return
        }

        let zeroBasedPage = min(max(pageNumber - 1, 0), document.pageCount - 1)
        guard let page = document.page(at: zeroBasedPage) else {
            return
        }

        context.coordinator.appliedProgressToken = token(for: progress)
        context.coordinator.isRestoringProgress = true
        pdfView.go(to: page)
        context.coordinator.isRestoringProgress = false
    }

    private func token(for progress: ReaderProgress) -> String {
        "\(progress.attachmentKey)|\(progress.location.displayLabel)|\(progress.updatedAt.timeIntervalSince1970)"
    }

    /// Draws stored highlight/underline records onto the in-memory
    /// document. The file on disk is never modified; records are
    /// re-anchored by searching their selected text on the stored page.
    private func applyAnnotationsIfNeeded(in pdfView: PDFView, context: Context) {
        let markings = annotations.filter { $0.kind != .note && $0.attachmentKey == attachment.objectKey }
        let annotationsToken = markings
            .map { "\($0.id)|\($0.kind.rawValue)|\($0.color.rawValue)" }
            .sorted()
            .joined(separator: ",")

        guard
            context.coordinator.appliedAnnotationsToken != annotationsToken,
            let document = pdfView.document
        else {
            return
        }

        for rendered in context.coordinator.renderedAnnotations {
            rendered.page?.removeAnnotation(rendered)
        }
        context.coordinator.renderedAnnotations = []

        for marking in markings {
            guard
                case let .page(pageNumber) = marking.location,
                let selectedText = marking.selectedText?.bcTrimmedNonEmpty,
                let page = document.page(at: min(max(pageNumber - 1, 0), document.pageCount - 1))
            else {
                continue
            }

            let matches = document.findString(selectedText, withOptions: [.caseInsensitive])
            guard let match = matches.first(where: { $0.pages.contains(page) }) ?? matches.first else {
                continue
            }

            let subtype: PDFAnnotationSubtype = marking.kind == .underline ? .underline : .highlight
            for lineSelection in match.selectionsByLine() {
                for linePage in lineSelection.pages {
                    let bounds = lineSelection.bounds(for: linePage)
                    guard !bounds.isEmpty else {
                        continue
                    }
                    let pdfAnnotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
                    pdfAnnotation.color = marking.color.nsColor.withAlphaComponent(
                        marking.kind == .underline ? 1.0 : 0.45
                    )
                    linePage.addAnnotation(pdfAnnotation)
                    context.coordinator.renderedAnnotations.append(pdfAnnotation)
                }
            }
        }

        context.coordinator.appliedAnnotationsToken = annotationsToken
    }
}

// MARK: - PDFSelectionInfo

struct PDFSelectionInfo {
    var text: String
    var pageNumber: Int
}

// MARK: - PDFViewProxy

/// Bridges the SwiftUI header actions to the underlying PDFView so
/// the highlight menu can read the user's current text selection.
@MainActor
final class PDFViewProxy {
    weak var pdfView: PDFView?

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
        guard index != NSNotFound else {
            return nil
        }
        return PDFSelectionInfo(text: text, pageNumber: index + 1)
    }
}
