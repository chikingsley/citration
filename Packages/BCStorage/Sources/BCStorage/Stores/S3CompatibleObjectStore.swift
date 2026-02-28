import Foundation

public struct S3CompatibleObjectStore: AttachmentObjectStore {
    public let connector: StorageConnector

    public init(connector: StorageConnector) {
        self.connector = connector
    }

    public func presignUpload(request: PresignUploadRequest) async throws -> PresignUploadResponse {
        throw ObjectStoreError.unsupportedOperation(
            "Presign upload is not implemented for connector type '\(connector.type.rawValue)' yet"
        )
    }

    public func presignDownload(objectKey: String) async throws -> URL {
        throw ObjectStoreError.unsupportedOperation(
            "Presign download is not implemented for connector type '\(connector.type.rawValue)' yet"
        )
    }

    public func completeMultipartUpload(_ request: CompleteMultipartUploadRequest) async throws {
        throw ObjectStoreError.unsupportedOperation(
            "Multipart completion is not implemented for connector type '\(connector.type.rawValue)' yet"
        )
    }

    public func deleteObject(objectKey: String) async throws {
        throw ObjectStoreError.unsupportedOperation(
            "Delete object is not implemented for connector type '\(connector.type.rawValue)' yet"
        )
    }
}
