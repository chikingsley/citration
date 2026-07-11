import Foundation

// MARK: - LegacyLibraryMigrationReport

public struct LegacyLibraryMigrationReport: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        sourceFingerprint: String,
        backupURL: URL,
        itemCount: Int,
        collectionCount: Int,
        membershipCount: Int,
        noteCount: Int,
        attachmentCount: Int,
        annotationCount: Int,
        relationshipCount: Int,
        readerProgressCount: Int
    ) {
        self.sourceFingerprint = sourceFingerprint
        self.backupURL = backupURL
        self.itemCount = itemCount
        self.collectionCount = collectionCount
        self.membershipCount = membershipCount
        self.noteCount = noteCount
        self.attachmentCount = attachmentCount
        self.annotationCount = annotationCount
        self.relationshipCount = relationshipCount
        self.readerProgressCount = readerProgressCount
    }

    // MARK: Public

    public let sourceFingerprint: String
    public let backupURL: URL
    public let itemCount: Int
    public let collectionCount: Int
    public let membershipCount: Int
    public let noteCount: Int
    public let attachmentCount: Int
    public let annotationCount: Int
    public let relationshipCount: Int
    public let readerProgressCount: Int

    public var zoteroItemObjectCount: Int {
        itemCount + noteCount + attachmentCount + annotationCount
    }
}

// MARK: - LegacyMigrationInspection

public struct LegacyMigrationInspection: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        status: String?,
        legacyRecordCount: Int,
        relationshipCount: Int,
        readerStateCount: Int,
        downloadedAttachmentCount: Int
    ) {
        self.status = status
        self.legacyRecordCount = legacyRecordCount
        self.relationshipCount = relationshipCount
        self.readerStateCount = readerStateCount
        self.downloadedAttachmentCount = downloadedAttachmentCount
    }

    // MARK: Public

    public let status: String?
    public let legacyRecordCount: Int
    public let relationshipCount: Int
    public let readerStateCount: Int
    public let downloadedAttachmentCount: Int
}

// MARK: - LegacyLibraryMigrationError

public enum LegacyLibraryMigrationError: Error, Equatable, Sendable {
    case missingItem(UUID, entityKind: String)
    case missingCollection(UUID)
    case verificationFailed(expected: LegacyMigrationInspection, actual: LegacyMigrationInspection)
}

// MARK: - LegacyMigrationObject

struct LegacyMigrationObject: Sendable {
    let entityKind: String
    let legacyID: String
    let rawPayload: Data
    let objectKind: ZoteroObjectKind?
    let objectKey: String?
}

// MARK: - LegacyMigrationProjection

struct LegacyMigrationProjection: Sendable {
    let collections: [ZoteroRawObject]
    let items: [ZoteroRawObject]
    let records: [LegacyMigrationObject]
    let relationships: [LegacyRelationshipProjection]
    let readerProgress: [LegacyReaderProgressProjection]
    let attachmentPaths: [(itemKey: String, fileURL: URL)]
}

// MARK: - LegacyRelationshipProjection

struct LegacyRelationshipProjection: Sendable {
    let relationship: LibraryRelationship
    let sourceKey: String
    let targetKey: String
    let rawPayload: Data
}

// MARK: - LegacyReaderProgressProjection

struct LegacyReaderProgressProjection: Sendable {
    let progress: ReaderProgress
    let itemKey: String
    let rawPayload: Data
}
