import CitrationCore
import Foundation
import PDFKit

// MARK: - IPadPDFAnnotationAnchor

struct IPadPDFAnnotationAnchor: Sendable {
    // MARK: Internal

    let pageIndex: Int
    let pageLabel: String
    let sortIndex: String
    let positionJSON: String

    static func ink(
        page: PDFPage,
        pageIndex: Int,
        paths: [[CGPoint]],
        width: CGFloat
    ) -> IPadPDFAnnotationAnchor? {
        guard let firstPoint = paths.first?.first, width > 0 else {
            return nil
        }
        let encodedPaths = paths.map { path in
            JSONValue.array(path.flatMap { point in
                [.number(point.x), .number(point.y)]
            })
        }
        let position = JSONValue.object([
            "pageIndex": .integer(Int64(pageIndex)),
            "paths": .array(encodedPaths),
            "width": .number(width),
        ])
        guard
            let data = try? ZoteroJSON.encode(position),
            let positionJSON = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return IPadPDFAnnotationAnchor(
            pageIndex: pageIndex,
            pageLabel: page.label ?? String(pageIndex + 1),
            sortIndex: sortIndex(page: page, pageIndex: pageIndex, point: firstPoint),
            positionJSON: positionJSON
        )
    }

    static func selection(
        page: PDFPage,
        pageIndex: Int,
        rects: [CGRect],
        nextPageRects: [CGRect] = []
    ) -> IPadPDFAnnotationAnchor? {
        guard let firstRect = rects.first else {
            return nil
        }
        var position: [String: JSONValue] = [
            "pageIndex": .integer(Int64(pageIndex)),
            "rects": .array(rects.map(rectValue)),
        ]
        if !nextPageRects.isEmpty {
            position["nextPageRects"] = .array(nextPageRects.map(rectValue))
        }
        guard
            let data = try? ZoteroJSON.encode(.object(position)),
            let positionJSON = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return IPadPDFAnnotationAnchor(
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

// MARK: - IPadPDFAnnotationRenderer

enum IPadPDFAnnotationRenderer {
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
            let subtype: PDFAnnotationSubtype = kind == .underline ? .underline : .highlight
            var rendered = renderRects(annotation.rects, subtype: subtype, annotation: annotation, page: page)
            if
                let nextPageIndex = annotation.nextPageIndex,
                nextPageIndex < document.pageCount,
                let nextPage = document.page(at: nextPageIndex)
            {
                rendered += renderRects(
                    annotation.nextPageRects,
                    subtype: subtype,
                    annotation: annotation,
                    page: nextPage
                )
            }
            return rendered

        case .note:
            guard let rect = annotation.rects.first.map(rectangle), !rect.isEmpty else {
                return []
            }
            let rendered = PDFAnnotation(bounds: rect, forType: .text, withProperties: nil)
            rendered.contents = annotation.comment
            rendered.color = color(annotation.color)
            page.addAnnotation(rendered)
            return [rendered]

        case .ink:
            return renderInk(annotation, page: page)
        }
    }

    static func inkAnnotation(
        paths: [[CGPoint]],
        width: CGFloat,
        color: UIColor
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
            let path = UIBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let first = points[0]
            path.move(to: CGPoint(x: first.x - bounds.minX, y: first.y - bounds.minY))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
            }
            rendered.add(path)
        }
        return rendered
    }

    // MARK: Private

    private static func renderRects(
        _ rects: [ZoteroAnnotationRect],
        subtype: PDFAnnotationSubtype,
        annotation: SynchronizedLibraryAnnotation,
        page: PDFPage
    ) -> [PDFAnnotation] {
        rects.compactMap { value in
            let bounds = rectangle(value)
            guard !bounds.isEmpty else {
                return nil
            }
            let rendered = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
            rendered.color = color(annotation.color).withAlphaComponent(subtype == .underline ? 1 : 0.45)
            rendered.contents = annotation.comment.isEmpty ? annotation.text : annotation.comment
            rendered.modificationDate = annotation.updatedAt
            rendered.userName = "Citration"
            page.addAnnotation(rendered)
            return rendered
        }
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
                color: color(annotation.color)
            )
        else {
            return []
        }
        rendered.contents = annotation.comment
        rendered.modificationDate = annotation.updatedAt
        rendered.userName = "Citration"
        page.addAnnotation(rendered)
        return [rendered]
    }

    private static func rectangle(_ rect: ZoteroAnnotationRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.maxX - rect.minX,
            height: rect.maxY - rect.minY
        )
    }

    private static func color(_ value: String) -> UIColor {
        switch value.lowercased() {
        case "#5fb236",
             "green": .systemGreen
        case "#2ea8e5",
             "blue": .systemBlue
        case "#e56eee",
             "pink": .systemPink
        case "#a28ae5",
             "purple": .systemPurple
        default: .systemYellow
        }
    }
}
