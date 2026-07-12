import CitrationCore
import PDFKit
import PencilKit
import SwiftUI

// MARK: - IPadPDFViewProxy

@MainActor
final class IPadPDFViewProxy {
    weak var pdfView: PDFView?

    func fitPage() {
        guard let pdfView else {
            return
        }
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.autoScales = true
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
    }

    func useContinuousLayout() {
        guard let pdfView else {
            return
        }
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
    }

    func fitWidth() {
        guard
            let pdfView,
            let page = pdfView.currentPage
        else {
            return
        }
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = false
        let pageWidth = page.bounds(for: pdfView.displayBox).width
        guard pageWidth > 0 else {
            return
        }
        pdfView.scaleFactor = max(pdfView.bounds.width / pageWidth, pdfView.minScaleFactor)
    }

    func selection() -> (text: String, anchor: IPadPDFAnnotationAnchor)? {
        guard
            let pdfView,
            let selection = pdfView.currentSelection,
            let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty,
            let page = selection.pages.first,
            let document = pdfView.document
        else {
            return nil
        }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, selection.pages.count <= 2 else {
            return nil
        }
        let lines = selection.selectionsByLine()
        let rects = lines.compactMap { line -> CGRect? in
            guard line.pages.contains(page) else {
                return nil
            }
            let bounds = line.bounds(for: page)
            return bounds.isEmpty ? nil : bounds
        }
        let nextRects: [CGRect] = if selection.pages.count == 2 {
            lines.compactMap { line -> CGRect? in
                let nextPage = selection.pages[1]
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
            let anchor = IPadPDFAnnotationAnchor.selection(
                page: page,
                pageIndex: pageIndex,
                rects: rects,
                nextPageRects: nextRects
            )
        else {
            return nil
        }
        return (text, anchor)
    }
}

// MARK: - IPadPDFRepresentable

struct IPadPDFRepresentable: UIViewRepresentable {
    // MARK: Internal

    final class ContainerView: UIView {
        // MARK: Lifecycle

        override init(frame: CGRect) {
            super.init(frame: frame)
            pdfView.translatesAutoresizingMaskIntoConstraints = false
            canvasView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(pdfView)
            addSubview(canvasView)
            NSLayoutConstraint.activate([
                pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
                pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
                pdfView.topAnchor.constraint(equalTo: topAnchor),
                pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
                canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
                canvasView.trailingAnchor.constraint(equalTo: trailingAnchor),
                canvasView.topAnchor.constraint(equalTo: topAnchor),
                canvasView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: Internal

        let pdfView: PDFView = .init()
        let canvasView: PKCanvasView = .init()
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        // MARK: Lifecycle

        init(parent: IPadPDFRepresentable) {
            self.parent = parent
        }

        // MARK: Internal

        var parent: IPadPDFRepresentable
        var loadedURL: URL?
        var renderedAnnotations: [PDFAnnotation] = []
        var annotationToken = ""
        var restoringProgress = false
        var drawingCommitTask: Task<Void, Never>?
        var isClearingDrawing = false
        weak var container: ContainerView?

        @objc
        func pageChanged(_ notification: Notification) {
            guard
                !restoringProgress,
                let pdfView = notification.object as? PDFView,
                let document = pdfView.document,
                let page = pdfView.currentPage
            else {
                return
            }
            let index = document.index(for: page)
            guard index != NSNotFound else {
                return
            }
            parent.onPageChange(index + 1, document.pageCount)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isClearingDrawing else {
                return
            }
            drawingCommitTask?.cancel()
            drawingCommitTask = Task { [weak self, weak canvasView] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self, let canvasView else {
                    return
                }
                commitDrawing(canvasView)
            }
        }

        // MARK: Private

        private func commitDrawing(_ canvasView: PKCanvasView) {
            guard
                let container,
                let document = container.pdfView.document,
                !canvasView.drawing.strokes.isEmpty
            else {
                return
            }
            let converted = canvasView.drawing.strokes.compactMap { stroke -> (PDFPage, [CGPoint])? in
                let points = stroke.path.compactMap { point -> (PDFPage, CGPoint)? in
                    let pdfViewPoint = container.pdfView.convert(point.location, from: canvasView)
                    guard let page = container.pdfView.page(for: pdfViewPoint, nearest: true) else {
                        return nil
                    }
                    return (page, container.pdfView.convert(pdfViewPoint, to: page))
                }
                guard
                    let page = points.first?.0,
                    points.allSatisfy({ $0.0 == page })
                else {
                    return nil
                }
                return (page, points.map(\.1))
            }
            guard
                let first = converted.first,
                converted.allSatisfy({ $0.0 == first.0 })
            else {
                isClearingDrawing = true
                canvasView.drawing = PKDrawing()
                isClearingDrawing = false
                return
            }
            let pageIndex = document.index(for: first.0)
            let width = parent.inkWidth
            let paths = converted.map(\.1)
            isClearingDrawing = true
            canvasView.drawing = PKDrawing()
            isClearingDrawing = false
            guard
                let anchor = IPadPDFAnnotationAnchor.ink(
                    page: first.0,
                    pageIndex: pageIndex,
                    paths: paths,
                    width: width
                )
            else {
                return
            }
            parent.onInk(anchor)
        }
    }

    let url: URL
    let progress: ReaderProgress?
    let annotations: [SynchronizedLibraryAnnotation]
    let isInkMode: Bool
    let inkColor: AnnotationColor
    let proxy: IPadPDFViewProxy
    let onPageChange: (Int, Int) -> Void
    let onInk: (IPadPDFAnnotationAnchor) -> Void

    var inkWidth: CGFloat {
        2.0
    }

    static func dismantleUIView(_ container: ContainerView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator, name: .PDFViewPageChanged, object: container.pdfView)
        coordinator.drawingCommitTask?.cancel()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ContainerView {
        let container = ContainerView()
        context.coordinator.container = container
        proxy.pdfView = container.pdfView
        container.pdfView.autoScales = true
        container.pdfView.displayMode = .singlePage
        container.pdfView.displayDirection = .horizontal
        container.pdfView.displaysPageBreaks = true
        container.canvasView.delegate = context.coordinator
        container.canvasView.backgroundColor = .clear
        container.canvasView.isOpaque = false
        container.canvasView.isScrollEnabled = false
        #if targetEnvironment(simulator)
            container.canvasView.drawingPolicy = .anyInput
        #else
            container.canvasView.drawingPolicy = .pencilOnly
        #endif
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: container.pdfView
        )
        load(in: container, coordinator: context.coordinator)
        return container
    }

    func updateUIView(_ container: ContainerView, context: Context) {
        context.coordinator.parent = self
        proxy.pdfView = container.pdfView
        if context.coordinator.loadedURL != url {
            load(in: container, coordinator: context.coordinator)
        }
        configureInk(in: container, coordinator: context.coordinator)
        applyProgress(in: container.pdfView, coordinator: context.coordinator)
        applyAnnotations(in: container.pdfView, coordinator: context.coordinator)
    }

    // MARK: Private

    private func load(in container: ContainerView, coordinator: Coordinator) {
        container.pdfView.document = PDFDocument(url: url)
        coordinator.loadedURL = url
        coordinator.annotationToken = ""
        applyProgress(in: container.pdfView, coordinator: coordinator)
        applyAnnotations(in: container.pdfView, coordinator: coordinator)
    }

    private func configureInk(in container: ContainerView, coordinator _: Coordinator) {
        container.canvasView.isUserInteractionEnabled = isInkMode
        container.canvasView.tool = PKInkingTool(.pen, color: uiColor(inkColor), width: inkWidth)
        if isInkMode {
            container.canvasView.becomeFirstResponder()
        } else {
            container.canvasView.resignFirstResponder()
        }
    }

    private func applyProgress(in pdfView: PDFView, coordinator: Coordinator) {
        guard
            let progress,
            case let .page(pageNumber) = progress.location,
            let document = pdfView.document,
            document.pageCount > 0,
            let page = document.page(at: min(max(pageNumber - 1, 0), document.pageCount - 1)),
            pdfView.currentPage != page
        else {
            return
        }
        coordinator.restoringProgress = true
        pdfView.go(to: page)
        coordinator.restoringProgress = false
    }

    private func applyAnnotations(in pdfView: PDFView, coordinator: Coordinator) {
        let token = annotations
            .map { "\($0.identity.objectKey)|\($0.version)|\($0.positionJSON)|\($0.color)|\($0.comment)" }
            .sorted()
            .joined(separator: ",")
        guard token != coordinator.annotationToken, let document = pdfView.document else {
            return
        }
        for annotation in coordinator.renderedAnnotations {
            annotation.page?.removeAnnotation(annotation)
        }
        coordinator.renderedAnnotations = annotations.flatMap {
            IPadPDFAnnotationRenderer.render($0, in: document)
        }
        coordinator.annotationToken = token
    }

    private func uiColor(_ color: AnnotationColor) -> UIColor {
        switch color {
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .pink: .systemPink
        case .purple: .systemPurple
        }
    }
}
