import Foundation

public struct LocalObjectStore: AttachmentObjectStore {
    public let connector: StorageConnector
    public let baseDirectory: URL

    public init(connector: StorageConnector, baseDirectory: URL) {
        self.connector = connector
        self.baseDirectory = baseDirectory
    }

    public func presignUpload(request: PresignUploadRequest) async throws -> PresignUploadResponse {
        guard request.contentLength >= 0 else {
            throw ObjectStoreError.invalidRequest("contentLength must be non-negative")
        }

        let filename = try sanitizeFilename(request.filename)
        let objectKey = "\(request.itemID.uuidString)/\(filename)"
        let uploadURL = baseDirectory.appendingPathComponent(objectKey)
        return PresignUploadResponse(
            objectKey: objectKey,
            uploadURL: uploadURL,
            requiredHeaders: [:],
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    public func presignDownload(objectKey: String) async throws -> URL {
        let validatedKey = try validateObjectKey(objectKey)
        return baseDirectory.appendingPathComponent(validatedKey)
    }

    public func completeMultipartUpload(_ request: CompleteMultipartUploadRequest) async throws {
        _ = try validateObjectKey(request.objectKey)
        guard !request.uploadID.isEmpty else {
            throw ObjectStoreError.invalidRequest("uploadID is required")
        }
        guard !request.parts.isEmpty else {
            throw ObjectStoreError.invalidRequest("at least one uploaded part is required")
        }
    }

    public func deleteObject(objectKey: String) async throws {
        _ = try validateObjectKey(objectKey)
    }

    private func sanitizeFilename(_ filename: String) throws -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ObjectStoreError.invalidRequest("filename is required")
        }
        guard !trimmed.contains("/") && !trimmed.contains("\\") else {
            throw ObjectStoreError.invalidRequest("filename must not contain path separators")
        }
        guard trimmed != "." && trimmed != ".." else {
            throw ObjectStoreError.invalidRequest("filename is invalid")
        }
        return trimmed
    }

    private func validateObjectKey(_ objectKey: String) throws -> String {
        let trimmed = objectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ObjectStoreError.invalidRequest("objectKey is required")
        }
        guard !trimmed.hasPrefix("/") else {
            throw ObjectStoreError.invalidRequest("objectKey must be relative")
        }
        guard !trimmed.contains("..") else {
            throw ObjectStoreError.invalidRequest("objectKey must not contain '..'")
        }
        guard !trimmed.contains("\\") else {
            throw ObjectStoreError.invalidRequest("objectKey must not contain backslashes")
        }
        return trimmed
    }
}
