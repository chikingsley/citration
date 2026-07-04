import Foundation

public enum DocumentFormat: String, Codable, CaseIterable, Sendable {
    case pdf
    case epub
    case html
    case plainText
    case image
    case audio
    case unknown

    public static func infer(fileName: String, contentType: String? = nil) -> DocumentFormat {
        let normalizedContentType = contentType?.lowercased()
        switch normalizedContentType {
        case "application/pdf":
            return .pdf
        case "application/epub+zip", "application/x-ibooks+zip":
            return .epub
        case "text/html", "application/xhtml+xml":
            return .html
        case "text/plain":
            return .plainText
        case let type? where type.hasPrefix("image/"):
            return .image
        case let type? where type.hasPrefix("audio/"):
            return .audio
        default:
            break
        }

        switch fileName.split(separator: ".").last?.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "html", "htm", "xhtml":
            return .html
        case "txt", "md", "markdown":
            return .plainText
        case "png", "jpg", "jpeg", "gif", "heic", "tiff":
            return .image
        case "mp3", "m4a", "aac", "wav", "aiff":
            return .audio
        default:
            return .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .pdf:
            return "PDF"
        case .epub:
            return "EPUB"
        case .html:
            return "HTML"
        case .plainText:
            return "Text"
        case .image:
            return "Image"
        case .audio:
            return "Audio"
        case .unknown:
            return "File"
        }
    }

    public var readerCapabilities: Set<ReaderCapability> {
        switch self {
        case .pdf:
            return [.pageNavigation, .textSelection, .annotations, .tableOfContents]
        case .epub:
            return [.reflowableText, .textSelection, .annotations, .tableOfContents]
        case .html, .plainText:
            return [.reflowableText, .textSelection, .annotations]
        case .audio:
            return [.timeNavigation]
        case .image, .unknown:
            return []
        }
    }

    public var isReadableDocument: Bool {
        !readerCapabilities.isEmpty
    }
}

public enum ReaderCapability: String, Codable, CaseIterable, Sendable {
    case pageNavigation
    case timeNavigation
    case reflowableText
    case textSelection
    case annotations
    case tableOfContents
}

public enum ReaderLocation: Hashable, Codable, Sendable {
    case page(Int)
    case epubCFI(String)
    case textOffset(Int)
    case time(seconds: Double)

    public var displayLabel: String {
        switch self {
        case .page(let page):
            return "Page \(page)"
        case .epubCFI:
            return "EPUB location"
        case .textOffset(let offset):
            return "Text offset \(offset)"
        case .time(let seconds):
            let minutes = Int(seconds) / 60
            let remainder = Int(seconds) % 60
            return "\(minutes):\(String(format: "%02d", remainder))"
        }
    }
}

public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case highlight
    case note
    case underline
}

public enum AnnotationColor: String, Codable, CaseIterable, Sendable {
    case yellow
    case green
    case blue
    case pink
    case purple
}

public struct LibraryAnnotation: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var itemID: UUID
    public var attachmentKey: String
    public var kind: AnnotationKind
    public var location: ReaderLocation?
    public var selectedText: String?
    public var note: String
    public var color: AnnotationColor
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        attachmentKey: String,
        kind: AnnotationKind = .note,
        location: ReaderLocation? = nil,
        selectedText: String? = nil,
        note: String,
        color: AnnotationColor = .yellow,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.itemID = itemID
        self.attachmentKey = attachmentKey
        self.kind = kind
        self.location = location
        self.selectedText = selectedText
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        note.isEmpty && (selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

public struct ReaderProgress: Identifiable, Hashable, Codable, Sendable {
    public var id: String { attachmentKey }
    public var itemID: UUID
    public var attachmentKey: String
    public var location: ReaderLocation
    public var fractionComplete: Double?
    public var updatedAt: Date

    public init(
        itemID: UUID,
        attachmentKey: String,
        location: ReaderLocation,
        fractionComplete: Double? = nil,
        updatedAt: Date = .now
    ) {
        self.itemID = itemID
        self.attachmentKey = attachmentKey
        self.location = location
        self.fractionComplete = fractionComplete.map { min(max($0, 0), 1) }
        self.updatedAt = updatedAt
    }
}

public struct LibraryCollection: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = Self.normalizedName(name) ?? "Untitled Collection"
        self.parentID = parentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func normalizedName(_ name: String) -> String? {
        let collapsed = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

public struct LibraryCollectionMembership: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var collectionID: UUID
    public var itemID: UUID
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        collectionID: UUID,
        itemID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.collectionID = collectionID
        self.itemID = itemID
        self.createdAt = createdAt
    }
}

public struct LibraryCollectionSnapshot: Hashable, Codable, Sendable {
    public var collections: [LibraryCollection]
    public var memberships: [LibraryCollectionMembership]

    public init(
        collections: [LibraryCollection] = [],
        memberships: [LibraryCollectionMembership] = []
    ) {
        self.collections = collections
        self.memberships = memberships
    }
}

public struct LibraryNote: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var itemID: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        text: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.itemID = itemID
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
