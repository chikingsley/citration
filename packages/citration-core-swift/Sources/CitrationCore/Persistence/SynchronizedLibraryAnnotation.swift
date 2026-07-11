import Foundation

// MARK: - ZoteroAnnotationRect

public struct ZoteroAnnotationRect: Hashable, Sendable {
    // MARK: Lifecycle

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    // MARK: Public

    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double
}

// MARK: - ZoteroAnnotationPoint

public struct ZoteroAnnotationPoint: Hashable, Sendable {
    // MARK: Lifecycle

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    // MARK: Public

    public let x: Double
    public let y: Double
}

// MARK: - SynchronizedLibraryAnnotation

public struct SynchronizedLibraryAnnotation: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        identity: SynchronizedLibraryItemIdentity,
        parentAttachmentIdentity: SynchronizedLibraryItemIdentity,
        bibliographicItemIdentity: SynchronizedLibraryItemIdentity,
        version: Int64,
        syncState: ZoteroSyncState,
        type: String,
        color: String,
        pageLabel: String,
        sortIndex: String,
        text: String,
        comment: String,
        positionJSON: String,
        tags: [ZoteroProjectedTag],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.identity = identity
        self.parentAttachmentIdentity = parentAttachmentIdentity
        self.bibliographicItemIdentity = bibliographicItemIdentity
        self.version = version
        self.syncState = syncState
        self.type = type
        self.color = color
        self.pageLabel = pageLabel
        self.sortIndex = sortIndex
        self.text = text
        self.comment = comment
        self.positionJSON = positionJSON
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: Public

    public let identity: SynchronizedLibraryItemIdentity
    public let parentAttachmentIdentity: SynchronizedLibraryItemIdentity
    public let bibliographicItemIdentity: SynchronizedLibraryItemIdentity
    public let version: Int64
    public let syncState: ZoteroSyncState
    public let type: String
    public let color: String
    public let pageLabel: String
    public let sortIndex: String
    public let text: String
    public let comment: String
    public let positionJSON: String
    public let tags: [ZoteroProjectedTag]
    public let createdAt: Date
    public let updatedAt: Date

    public var id: SynchronizedLibraryItemIdentity {
        identity
    }

    public var kind: AnnotationKind? {
        AnnotationKind(rawValue: type)
    }

    public var pageIndex: Int? {
        positionObject?["pageIndex"]?.integerValue.map(Int.init)
    }

    public var location: ReaderLocation? {
        if let pageIndex {
            return .page(pageIndex + 1)
        }
        if let cfi = positionObject?["epubCFI"]?.stringValue {
            return .epubCFI(cfi)
        }
        if let offset = positionObject?["textOffset"]?.integerValue {
            return .textOffset(Int(offset))
        }
        if let seconds = positionObject?["seconds"]?.numberValue {
            return .time(seconds: seconds)
        }
        return nil
    }

    public var rects: [ZoteroAnnotationRect] {
        Self.decodeRects(positionObject?["rects"])
    }

    public var nextPageRects: [ZoteroAnnotationRect] {
        Self.decodeRects(positionObject?["nextPageRects"])
    }

    public var nextPageIndex: Int? {
        nextPageRects.isEmpty ? nil : pageIndex.map { $0 + 1 }
    }

    public var inkPaths: [[ZoteroAnnotationPoint]] {
        (positionObject?["paths"]?.arrayValue ?? []).compactMap { pathValue in
            guard let coordinates = pathValue.arrayValue, coordinates.count.isMultiple(of: 2) else {
                return nil
            }
            var points = [ZoteroAnnotationPoint]()
            for index in stride(from: 0, to: coordinates.count, by: 2) {
                guard
                    let x = coordinates[index].numberValue,
                    let y = coordinates[index + 1].numberValue
                else {
                    return nil
                }
                points.append(ZoteroAnnotationPoint(x: x, y: y))
            }
            return points
        }
    }

    public var inkWidth: Double? {
        positionObject?["width"]?.numberValue
    }

    public func compatibilityAnnotation() -> LibraryAnnotation {
        LibraryAnnotation(
            id: identity.appUUID,
            itemID: bibliographicItemIdentity.appUUID,
            attachmentKey: parentAttachmentIdentity.objectKey,
            kind: kind ?? .note,
            location: location,
            selectedText: text.isEmpty ? nil : text,
            note: comment,
            color: Self.annotationColor(from: color),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: Private

    private var positionObject: [String: JSONValue]? {
        guard let data = positionJSON.data(using: .utf8) else {
            return nil
        }
        return try? ZoteroJSON.decode(data).objectValue
    }

    private static func decodeRects(_ value: JSONValue?) -> [ZoteroAnnotationRect] {
        (value?.arrayValue ?? []).compactMap { value in
            guard
                let coordinates = value.arrayValue,
                coordinates.count == 4,
                let minX = coordinates[0].numberValue,
                let minY = coordinates[1].numberValue,
                let maxX = coordinates[2].numberValue,
                let maxY = coordinates[3].numberValue
            else {
                return nil
            }
            return ZoteroAnnotationRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        }
    }

    private static func annotationColor(from value: String) -> AnnotationColor {
        switch value.lowercased() {
        case "#5fb236",
             "green": .green
        case "#2ea8e5",
             "blue": .blue
        case "#e56eee",
             "pink": .pink
        case "#a28ae5",
             "purple": .purple
        default: .yellow
        }
    }
}

// MARK: - SynchronizedLibraryAnnotationStoring

public protocol SynchronizedLibraryAnnotationStoring: LibraryAnnotationStoring {
    func annotationContext(
        itemID: UUID,
        attachmentKey: String
    ) async throws -> SynchronizedLibraryAnnotationContext

    func listSynchronizedAnnotations(
        itemID: UUID,
        attachmentKey: String?
    ) async throws -> [SynchronizedLibraryAnnotation]

    func createSynchronizedAnnotation(
        _ draft: SynchronizedLibraryAnnotationDraft
    ) async throws -> SynchronizedLibraryAnnotation

    func updateSynchronizedAnnotation(
        _ update: SynchronizedLibraryAnnotationUpdate
    ) async throws -> SynchronizedLibraryAnnotation
}
