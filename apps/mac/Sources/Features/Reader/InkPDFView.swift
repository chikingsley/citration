import AppKit
import CitrationCore
import PDFKit

// MARK: - PDFInkStrokeInfo

struct PDFInkStrokeInfo: Sendable {
    let anchor: PDFAnnotationAnchor
}

// MARK: - InkPDFView

@MainActor
final class InkPDFView: PDFView {
    // MARK: Internal

    var inkColor: NSColor = .systemYellow
    var inkWidth: CGFloat = 1.5
    var onInkStroke: ((PDFInkStrokeInfo) -> Void)?

    var isInkMode = false {
        didSet {
            if !isInkMode {
                cancelStroke()
            }
            if let window {
                window.invalidateCursorRects(for: self)
            }
        }
    }

    override func resetCursorRects() {
        guard isInkMode else {
            super.resetCursorRects()
            return
        }
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard
            isInkMode,
            let document,
            let page = drawingPage(for: event),
            document.index(for: page) != NSNotFound
        else {
            super.mouseDown(with: event)
            return
        }
        drawingPage = page
        strokePoints = [pagePoint(for: event, on: page)]
        updatePreview()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInkMode, let drawingPage else {
            super.mouseDragged(with: event)
            return
        }
        append(pagePoint(for: event, on: drawingPage))
        updatePreview()
    }

    override func mouseUp(with event: NSEvent) {
        guard
            isInkMode,
            let drawingPage,
            let document,
            document.index(for: drawingPage) != NSNotFound
        else {
            super.mouseUp(with: event)
            return
        }
        append(pagePoint(for: event, on: drawingPage))
        let pageIndex = document.index(for: drawingPage)
        let anchor = PDFAnnotationAnchor.ink(
            page: drawingPage,
            pageIndex: pageIndex,
            points: strokePoints,
            width: inkWidth
        )
        cancelStroke()
        if let anchor {
            onInkStroke?(PDFInkStrokeInfo(anchor: anchor))
        }
    }

    // MARK: Private

    private var drawingPage: PDFPage?
    private var strokePoints: [CGPoint] = []
    private var previewAnnotation: PDFAnnotation?

    private func drawingPage(for event: NSEvent) -> PDFPage? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return page(for: viewPoint, nearest: true)
    }

    private func pagePoint(for event: NSEvent, on page: PDFPage) -> CGPoint {
        let point = convert(convert(event.locationInWindow, from: nil), to: page)
        let bounds = page.bounds(for: .cropBox)
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func append(_ point: CGPoint) {
        guard let last = strokePoints.last else {
            strokePoints.append(point)
            return
        }
        guard hypot(point.x - last.x, point.y - last.y) >= 0.35 else {
            return
        }
        strokePoints.append(point)
    }

    private func updatePreview() {
        if let previewAnnotation {
            previewAnnotation.page?.removeAnnotation(previewAnnotation)
        }
        guard
            let drawingPage,
            let annotation = ZoteroPDFAnnotationRenderer.inkAnnotation(
                paths: [strokePoints],
                width: inkWidth,
                color: inkColor
            )
        else {
            previewAnnotation = nil
            return
        }
        drawingPage.addAnnotation(annotation)
        previewAnnotation = annotation
    }

    private func cancelStroke() {
        if let previewAnnotation {
            previewAnnotation.page?.removeAnnotation(previewAnnotation)
        }
        drawingPage = nil
        strokePoints = []
        previewAnnotation = nil
    }
}
