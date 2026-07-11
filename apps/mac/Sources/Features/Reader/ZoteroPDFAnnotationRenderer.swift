import CitrationCore
import PDFKit

enum ZoteroPDFAnnotationRenderer {
    // MARK: Internal

    static func render(
        _ annotation: SynchronizedLibraryAnnotation,
        in document: PDFDocument
    ) -> [PDFAnnotation] {
        guard
            let kind = annotation.kind,
            let pageIndex = annotation.pageIndex,
            pageIndex >= 0,
            pageIndex < document.pageCount,
            let page = document.page(at: pageIndex)
        else {
            return []
        }

        switch kind {
        case .highlight,
             .underline:
            return renderMarking(annotation, kind: kind, page: page, document: document)
        case .note:
            return renderNote(annotation, page: page)
        case .ink:
            return renderInk(annotation, page: page)
        }
    }

    static func inkAnnotation(
        paths: [[CGPoint]],
        width: CGFloat,
        color: NSColor
    ) -> PDFAnnotation? {
        let points = paths.flatMap(\.self)
        guard
            let minX = points.map(\.x).min(),
            let minY = points.map(\.y).min(),
            let maxX = points.map(\.x).max(),
            let maxY = points.map(\.y).max()
        else {
            return nil
        }
        let padding = max(width, 1)
        let bounds = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: max(maxX - minX + padding * 2, padding * 2),
            height: max(maxY - minY + padding * 2, padding * 2)
        )
        let rendered = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        rendered.color = color
        let border = PDFBorder()
        border.lineWidth = width
        rendered.border = border
        for points in paths where !points.isEmpty {
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let first = points[0]
            path.move(to: CGPoint(x: first.x - bounds.minX, y: first.y - bounds.minY))
            if points.count == 1 {
                path.line(to: CGPoint(x: first.x - bounds.minX, y: first.y - bounds.minY))
            } else {
                for point in points.dropFirst() {
                    path.line(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
                }
            }
            rendered.add(path)
        }
        return rendered
    }

    // MARK: Private

    private static func renderMarking(
        _ annotation: SynchronizedLibraryAnnotation,
        kind: AnnotationKind,
        page: PDFPage,
        document: PDFDocument
    ) -> [PDFAnnotation] {
        let primaryBounds = annotation.rects.map(rectangle)
        let resolvedBounds = primaryBounds.isEmpty
            ? fallbackBounds(for: annotation.text, on: page, in: document)
            : primaryBounds
        let subtype: PDFAnnotationSubtype = kind == .underline ? .underline : .highlight
        var rendered = addMarkings(resolvedBounds, subtype: subtype, annotation: annotation, to: page)
        if
            let nextPageIndex = annotation.nextPageIndex,
            nextPageIndex < document.pageCount,
            let nextPage = document.page(at: nextPageIndex)
        {
            rendered += addMarkings(
                annotation.nextPageRects.map(rectangle),
                subtype: subtype,
                annotation: annotation,
                to: nextPage
            )
        }
        return rendered
    }

    private static func addMarkings(
        _ boundsList: [CGRect],
        subtype: PDFAnnotationSubtype,
        annotation: SynchronizedLibraryAnnotation,
        to page: PDFPage
    ) -> [PDFAnnotation] {
        boundsList.compactMap { bounds in
            guard !bounds.isEmpty else {
                return nil
            }
            let rendered = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
            rendered.color = annotation.compatibilityAnnotation().color.nsColor.withAlphaComponent(
                subtype == .underline ? 1 : 0.45
            )
            applyMetadata(annotation, to: rendered)
            page.addAnnotation(rendered)
            return rendered
        }
    }

    private static func renderNote(
        _ annotation: SynchronizedLibraryAnnotation,
        page: PDFPage
    ) -> [PDFAnnotation] {
        guard let bounds = annotation.rects.first.map(rectangle), !bounds.isEmpty else {
            return []
        }
        let rendered = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        rendered.contents = annotation.comment
        rendered.color = annotation.compatibilityAnnotation().color.nsColor
        applyMetadata(annotation, to: rendered)
        page.addAnnotation(rendered)
        return [rendered]
    }

    private static func renderInk(
        _ annotation: SynchronizedLibraryAnnotation,
        page: PDFPage
    ) -> [PDFAnnotation] {
        let paths = annotation.inkPaths.map { path in
            path.map { CGPoint(x: $0.x, y: $0.y) }
        }
        guard
            let rendered = inkAnnotation(
                paths: paths,
                width: annotation.inkWidth ?? 1,
                color: annotation.compatibilityAnnotation().color.nsColor
            )
        else {
            return []
        }
        applyMetadata(annotation, to: rendered)
        page.addAnnotation(rendered)
        return [rendered]
    }

    private static func fallbackBounds(
        for text: String,
        on page: PDFPage,
        in document: PDFDocument
    ) -> [CGRect] {
        guard !text.isEmpty else {
            return []
        }
        let matches = document.findString(text, withOptions: [.caseInsensitive])
        guard let match = matches.first(where: { $0.pages.contains(page) }) else {
            return []
        }
        return match.selectionsByLine().flatMap { selection in
            selection.pages.compactMap { linePage in
                guard linePage == page else {
                    return nil
                }
                return selection.bounds(for: linePage)
            }
        }
    }

    private static func rectangle(_ rect: ZoteroAnnotationRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.maxX - rect.minX,
            height: rect.maxY - rect.minY
        )
    }

    private static func applyMetadata(
        _ annotation: SynchronizedLibraryAnnotation,
        to rendered: PDFAnnotation
    ) {
        rendered.contents = annotation.comment.bcTrimmedNonEmpty ?? annotation.text.bcTrimmedNonEmpty
        rendered.modificationDate = annotation.updatedAt
        rendered.userName = "Citration"
    }
}
