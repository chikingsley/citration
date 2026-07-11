import Foundation

// MARK: - DocumentFormat

public enum DocumentFormat: String, Codable, CaseIterable, Sendable {
    case pdf
    case epub
    case html
    case plainText
    case image
    case audio
    case unknown

    // MARK: Public

    public var displayName: String {
        switch self {
        case .pdf:
            "PDF"
        case .epub:
            "EPUB"
        case .html:
            "HTML"
        case .plainText:
            "Text"
        case .image:
            "Image"
        case .audio:
            "Audio"
        case .unknown:
            "File"
        }
    }

    public var readerCapabilities: Set<ReaderCapability> {
        switch self {
        case .pdf:
            [.pageNavigation, .textSelection, .annotations, .tableOfContents]
        case .epub:
            [.reflowableText, .textSelection, .annotations, .tableOfContents]
        case .html,
             .plainText:
            [.reflowableText, .textSelection, .annotations]
        case .audio:
            [.timeNavigation]
        case .image,
             .unknown:
            []
        }
    }

    public var isReadableDocument: Bool {
        !readerCapabilities.isEmpty
    }

    public var isSupportedInApp: Bool {
        switch self {
        case .pdf,
             .epub,
             .html,
             .plainText:
            true
        case .image,
             .audio,
             .unknown:
            false
        }
    }

    public static func infer(fileName: String, contentType: String? = nil) -> DocumentFormat {
        let normalizedContentType = contentType?.lowercased()
        switch normalizedContentType {
        case "application/pdf":
            return .pdf
        case "application/epub+zip",
             "application/x-ibooks+zip":
            return .epub
        case "text/html",
             "application/xhtml+xml":
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
        case "html",
             "htm",
             "xhtml":
            return .html
        case "txt",
             "md",
             "markdown":
            return .plainText
        case "png",
             "jpg",
             "jpeg",
             "gif",
             "heic",
             "tiff":
            return .image
        case "mp3",
             "m4a",
             "aac",
             "wav",
             "aiff":
            return .audio
        default:
            return .unknown
        }
    }
}

// MARK: - ReaderCapability

public enum ReaderCapability: String, Codable, CaseIterable, Sendable {
    case pageNavigation
    case timeNavigation
    case reflowableText
    case textSelection
    case annotations
    case tableOfContents
}

// MARK: - ReaderLocation

public enum ReaderLocation: Hashable, Codable, Sendable {
    case page(Int)
    case epubCFI(String)
    case textOffset(Int)
    case time(seconds: Double)

    // MARK: Public

    public var displayLabel: String {
        switch self {
        case let .page(page):
            return "Page \(page)"
        case .epubCFI:
            return "EPUB location"
        case let .textOffset(offset):
            return "Text offset \(offset)"
        case let .time(seconds):
            let minutes = Int(seconds) / 60
            let remainder = Int(seconds) % 60
            return "\(minutes):\(String(format: "%02d", remainder))"
        }
    }
}

// MARK: - AnnotationKind

public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case highlight
    case ink
    case note
    case underline
}

// MARK: - AnnotationColor

public enum AnnotationColor: String, Codable, CaseIterable, Sendable {
    case yellow
    case green
    case blue
    case pink
    case purple
}

// MARK: - LibraryAnnotation

public struct LibraryAnnotation: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

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

    // MARK: Public

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

    public var isEmpty: Bool {
        note.isEmpty && (selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

// MARK: - ReaderProgress

public struct ReaderProgress: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

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

    // MARK: Public

    public var itemID: UUID
    public var attachmentKey: String
    public var location: ReaderLocation
    public var fractionComplete: Double?
    public var updatedAt: Date

    public var id: String {
        attachmentKey
    }
}

// MARK: - LibraryCollection

public struct LibraryCollection: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

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

    // MARK: Public

    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public static func normalizedName(_ name: String) -> String? {
        let collapsed = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

// MARK: - LibraryCollectionMembership

public struct LibraryCollectionMembership: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

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

    // MARK: Public

    public var id: UUID
    public var collectionID: UUID
    public var itemID: UUID
    public var createdAt: Date
}

// MARK: - LibraryCollectionSnapshot

public struct LibraryCollectionSnapshot: Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(
        collections: [LibraryCollection] = [],
        memberships: [LibraryCollectionMembership] = []
    ) {
        self.collections = collections
        self.memberships = memberships
    }

    // MARK: Public

    public var collections: [LibraryCollection]
    public var memberships: [LibraryCollectionMembership]
}

// MARK: - LibraryNote

public struct LibraryNote: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

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

    // MARK: Public

    public var id: UUID
    public var itemID: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
