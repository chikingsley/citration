import Foundation

// MARK: - LibraryAttachment

public struct LibraryAttachment: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        itemID: UUID,
        fileName: String,
        objectKey: String,
        localURL: URL,
        contentType: String,
        size: Int64,
        createdAt: Date
    ) {
        self.itemID = itemID
        self.fileName = fileName
        self.objectKey = objectKey
        self.localURL = localURL
        self.contentType = contentType
        self.size = size
        self.createdAt = createdAt
    }

    // MARK: Public

    public let itemID: UUID
    public let fileName: String
    public let objectKey: String
    public let localURL: URL
    public let contentType: String
    public let size: Int64
    public let createdAt: Date

    public var id: String {
        objectKey
    }

    public var documentFormat: DocumentFormat {
        DocumentFormat.infer(fileName: fileName, contentType: contentType)
    }
}

// MARK: - LibraryCollectionStoring

public protocol LibraryCollectionStoring: Sendable {
    func snapshot() async throws -> LibraryCollectionSnapshot
    func createCollection(name: String, parentID: UUID?) async throws -> LibraryCollection
    func removeCollection(id: UUID) async throws
    func addItem(_ itemID: UUID, to collectionID: UUID) async throws -> LibraryCollectionMembership
    func removeItem(_ itemID: UUID, from collectionID: UUID) async throws
    func removeItems(ids: [UUID]) async throws
}

public extension LibraryCollectionStoring {
    func createCollection(name: String) async throws -> LibraryCollection {
        try await createCollection(name: name, parentID: nil)
    }
}

// MARK: - LibraryNoteStoring

public protocol LibraryNoteStoring: Sendable {
    func listNotes(itemID: UUID?) async throws -> [LibraryNote]
    func upsert(_ note: LibraryNote) async throws -> LibraryNote
    func remove(id: UUID) async throws
    func removeNotes(itemIDs: [UUID]) async throws
}

// MARK: - LibraryAnnotationStoring

public protocol LibraryAnnotationStoring: Sendable {
    func listAnnotations(itemID: UUID, attachmentKey: String?) async throws -> [LibraryAnnotation]
    func upsert(_ annotation: LibraryAnnotation) async throws -> LibraryAnnotation
    func remove(id: UUID) async throws
}

// MARK: - LibraryRelationshipStoring

public protocol LibraryRelationshipStoring: Sendable {
    func listRelationships(itemID: UUID?) async throws -> [LibraryRelationship]
    func upsert(_ relationship: LibraryRelationship) async throws -> LibraryRelationship
    func remove(id: UUID) async throws
    func removeRelationships(itemIDs: [UUID]) async throws
}

public extension LibraryRelationshipStoring {
    func listRelationships() async throws -> [LibraryRelationship] {
        try await listRelationships(itemID: nil)
    }
}

// MARK: - LibraryReaderProgressStoring

public protocol LibraryReaderProgressStoring: Sendable {
    func progress(for attachmentKey: String) async throws -> ReaderProgress?
    func listProgress(itemID: UUID?) async throws -> [ReaderProgress]
    func upsert(_ progress: ReaderProgress) async throws -> ReaderProgress
    func remove(attachmentKey: String) async throws
    func removeProgress(itemIDs: [UUID]) async throws
}

// MARK: - LibraryAttachmentStoring

public protocol LibraryAttachmentStoring: Sendable {
    func importFile(from sourceURL: URL, for item: BCItem) async throws -> LibraryAttachment
    func listAttachments(for itemID: UUID) async throws -> [LibraryAttachment]
    func removeAttachment(_ attachment: LibraryAttachment) async throws
}
