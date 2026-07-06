import Foundation

// MARK: - StorageConnectorType

public enum StorageConnectorType: String, Codable, CaseIterable, Sendable {
    case local
    case s3
    case r2
    case supabaseS3 = "supabase-s3"
    case minio
}

// MARK: - StorageConnector

public struct StorageConnector: Identifiable, Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        name: String,
        type: StorageConnectorType,
        endpoint: URL? = nil,
        region: String? = nil,
        bucket: String,
        forcePathStyle: Bool = false,
        isDefault: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.forcePathStyle = forcePathStyle
        self.isDefault = isDefault
        self.metadata = metadata
    }

    // MARK: Public

    public var id: UUID
    public var name: String
    public var type: StorageConnectorType
    public var endpoint: URL?
    public var region: String?
    public var bucket: String
    public var forcePathStyle: Bool
    public var isDefault: Bool
    public var metadata: [String: String]
}

// MARK: - PresignUploadRequest

public struct PresignUploadRequest: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        itemID: UUID,
        filename: String,
        contentType: String,
        contentLength: Int64,
        checksumSHA256: String? = nil
    ) {
        self.itemID = itemID
        self.filename = filename
        self.contentType = contentType
        self.contentLength = contentLength
        self.checksumSHA256 = checksumSHA256
    }

    // MARK: Public

    public var itemID: UUID
    public var filename: String
    public var contentType: String
    public var contentLength: Int64
    public var checksumSHA256: String?
}

// MARK: - PresignUploadResponse

public struct PresignUploadResponse: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        objectKey: String,
        uploadURL: URL,
        requiredHeaders: [String: String] = [:],
        expiresAt: Date
    ) {
        self.objectKey = objectKey
        self.uploadURL = uploadURL
        self.requiredHeaders = requiredHeaders
        self.expiresAt = expiresAt
    }

    // MARK: Public

    public var objectKey: String
    public var uploadURL: URL
    public var requiredHeaders: [String: String]
    public var expiresAt: Date
}

// MARK: - UploadedPart

public struct UploadedPart: Hashable, Sendable {
    // MARK: Lifecycle

    public init(partNumber: Int, etag: String) {
        self.partNumber = partNumber
        self.etag = etag
    }

    // MARK: Public

    public var partNumber: Int
    public var etag: String
}

// MARK: - CompleteMultipartUploadRequest

public struct CompleteMultipartUploadRequest: Hashable, Sendable {
    // MARK: Lifecycle

    public init(objectKey: String, uploadID: String, parts: [UploadedPart]) {
        self.objectKey = objectKey
        self.uploadID = uploadID
        self.parts = parts
    }

    // MARK: Public

    public var objectKey: String
    public var uploadID: String
    public var parts: [UploadedPart]
}

// MARK: - ObjectStoreError

public enum ObjectStoreError: Error, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case invalidRequest(String)
    case unsupportedOperation(String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(details):
            "Invalid storage connector configuration: \(details)"
        case let .invalidRequest(details):
            "Invalid object-store request: \(details)"
        case let .unsupportedOperation(details):
            "Unsupported object-store operation: \(details)"
        }
    }
}

// MARK: - AttachmentObjectStore

public protocol AttachmentObjectStore: Sendable {
    var connector: StorageConnector { get }

    func presignUpload(request: PresignUploadRequest) async throws -> PresignUploadResponse
    func presignDownload(objectKey: String) async throws -> URL
    func completeMultipartUpload(_ request: CompleteMultipartUploadRequest) async throws
    func deleteObject(objectKey: String) async throws
}
