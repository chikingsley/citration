import CitrationCore
import Foundation

// MARK: - WorkspaceTab

enum WorkspaceTab: Hashable {
    case library
    case document(String)
}

// MARK: - DocumentSession

@MainActor
final class DocumentSession: Identifiable {
    // MARK: Lifecycle

    init(attachment: LocalAttachment, reader: ReaderModel) {
        id = attachment.objectKey
        self.attachment = attachment
        self.reader = reader
    }

    // MARK: Internal

    nonisolated let id: String
    var attachment: LocalAttachment
    let reader: ReaderModel
}

// MARK: - DocumentWindowRoute

struct DocumentWindowRoute: Codable, Hashable {
    // MARK: Lifecycle

    init(attachment: LocalAttachment) {
        itemID = attachment.itemID
        fileName = attachment.fileName
        objectKey = attachment.objectKey
        localURL = attachment.localURL
        contentType = attachment.contentType
        size = attachment.size
        createdAt = attachment.createdAt
    }

    // MARK: Internal

    let itemID: UUID
    let fileName: String
    let objectKey: String
    let localURL: URL
    let contentType: String
    let size: Int64
    let createdAt: Date

    var attachment: LocalAttachment {
        LocalAttachment(
            itemID: itemID,
            fileName: fileName,
            objectKey: objectKey,
            localURL: localURL,
            contentType: contentType,
            size: size,
            createdAt: createdAt
        )
    }
}
