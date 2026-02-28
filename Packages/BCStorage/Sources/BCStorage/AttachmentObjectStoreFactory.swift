import Foundation

public struct AttachmentObjectStoreFactory: Sendable {
    public init() {}

    public func makeStore(
        connector: StorageConnector,
        localBaseDirectory: URL
    ) -> any AttachmentObjectStore {
        switch connector.type {
        case .local:
            return LocalObjectStore(connector: connector, baseDirectory: localBaseDirectory)
        case .s3, .r2, .supabaseS3, .minio:
            return S3CompatibleObjectStore(connector: connector)
        }
    }
}
