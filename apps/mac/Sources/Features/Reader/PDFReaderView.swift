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
    let annotations: [SynchronizedLibraryAnnotation]
    let proxy: PDFViewProxy
    let isInkMode: Bool
    let inkColor: AnnotationColor
    let onInkStroke: (PDFInkStrokeInfo) -> Void
    let onProgressChange: (ReaderProgress) -> Void

    static func dismantleNSView(_ nsView: InkPDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewPageChanged,
            object: nsView
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> InkPDFView {
        let pdfView = InkPDFView()
        proxy.pdfView = pdfView
        context.coordinator.configure(attachment: attachment, onProgressChange: onProgressChange)
        configureInk(in: pdfView)
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

    func updateNSView(_ pdfView: InkPDFView, context: Context) {
        proxy.pdfView = pdfView
        context.coordinator.configure(attachment: attachment, onProgressChange: onProgressChange)
        configureInk(in: pdfView)
        guard context.coordinator.loadedURL != attachment.localURL else {
            applyProgressIfNeeded(in: pdfView, context: context)
            applyAnnotationsIfNeeded(in: pdfView, context: context)
            return
        }
        loadDocument(in: pdfView, context: context)
    }

    // MARK: Private

    private func configureInk(in pdfView: InkPDFView) {
        pdfView.isInkMode = isInkMode
        pdfView.inkColor = inkColor.nsColor
        pdfView.onInkStroke = onInkStroke
    }

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
        let markings = annotations.filter {
            $0.parentAttachmentIdentity.objectKey == attachment.objectKey
        }
        let annotationsToken = markings
            .map { "\($0.identity.objectKey)|\($0.version)|\($0.positionJSON)|\($0.color)|\($0.comment)" }
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
            context.coordinator.renderedAnnotations += ZoteroPDFAnnotationRenderer.render(
                marking,
                in: document
            )
        }

        context.coordinator.appliedAnnotationsToken = annotationsToken
    }
}

// MARK: - PDFAnnotationAnchor

struct PDFAnnotationAnchor: Sendable {
    // MARK: Internal

    let pageIndex: Int
    let pageLabel: String
    let sortIndex: String
    let positionJSON: String

    static func note(for attachment: LocalAttachment, pageNumber: Int) -> PDFAnnotationAnchor? {
        guard
            let document = PDFDocument(url: attachment.localURL),
            document.pageCount > 0,
            let page = document.page(at: min(max(pageNumber - 1, 0), document.pageCount - 1))
        else {
            return nil
        }
        let pageIndex = document.index(for: page)
        let pageBounds = page.bounds(for: .cropBox)
        let size = 22.0
        let rect = CGRect(
            x: max(pageBounds.maxX - size - 20, pageBounds.minX),
            y: max(pageBounds.maxY - size - 20, pageBounds.minY),
            width: size,
            height: size
        )
        return make(page: page, pageIndex: pageIndex, primaryRects: [rect], nextPageRects: [])
    }

    static func ink(
        page: PDFPage,
        pageIndex: Int,
        points: [CGPoint],
        width: CGFloat
    ) -> PDFAnnotationAnchor? {
        guard let firstPoint = points.first, width > 0 else {
            return nil
        }
        let path = points.flatMap { point in
            [JSONValue.number(point.x), .number(point.y)]
        }
        let position = JSONValue.object([
            "pageIndex": .integer(Int64(pageIndex)),
            "paths": .array([.array(path)]),
            "width": .number(width),
        ])
        guard
            let positionData = try? ZoteroJSON.encode(position),
            let positionJSON = String(data: positionData, encoding: .utf8)
        else {
            return nil
        }
        return PDFAnnotationAnchor(
            pageIndex: pageIndex,
            pageLabel: page.label ?? String(pageIndex + 1),
            sortIndex: sortIndex(page: page, pageIndex: pageIndex, point: firstPoint),
            positionJSON: positionJSON
        )
    }

    // MARK: Fileprivate

    fileprivate static func make(
        page: PDFPage,
        pageIndex: Int,
        primaryRects: [CGRect],
        nextPageRects: [CGRect]
    ) -> PDFAnnotationAnchor? {
        guard let firstRect = primaryRects.first else {
            return nil
        }
        var position: [String: JSONValue] = [
            "pageIndex": .integer(Int64(pageIndex)),
            "rects": .array(primaryRects.map(rectValue)),
        ]
        if !nextPageRects.isEmpty {
            position["nextPageRects"] = .array(nextPageRects.map(rectValue))
        }
        guard
            let positionData = try? ZoteroJSON.encode(.object(position)),
            let positionJSON = String(data: positionData, encoding: .utf8)
        else {
            return nil
        }
        return PDFAnnotationAnchor(
            pageIndex: pageIndex,
            pageLabel: page.label ?? String(pageIndex + 1),
            sortIndex: sortIndex(
                page: page,
                pageIndex: pageIndex,
                point: CGPoint(x: firstRect.minX + 1, y: firstRect.maxY)
            ),
            positionJSON: positionJSON
        )
    }

    // MARK: Private

    private static func rectValue(_ rect: CGRect) -> JSONValue {
        .array([
            .number(rect.minX),
            .number(rect.minY),
            .number(rect.maxX),
            .number(rect.maxY),
        ])
    }

    private static func sortIndex(page: PDFPage, pageIndex: Int, point: CGPoint) -> String {
        let characterIndex = page.characterIndex(at: point)
        let offset = characterIndex == NSNotFound ? 0 : max(characterIndex, 0)
        let top = max(Int(floor(page.bounds(for: .cropBox).maxY - point.y)), 0)
        return String(format: "%05d|%06d|%05d", pageIndex, offset, top)
    }
}

// MARK: - PDFSelectionInfo

struct PDFSelectionInfo: Sendable {
    let text: String
    let anchor: PDFAnnotationAnchor
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
}
