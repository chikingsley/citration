import Foundation

public struct AttachmentObjectStoreFactory: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public func makeStore(
        connector: StorageConnector,
        localBaseDirectory: URL
    ) -> any AttachmentObjectStore {
        switch connector.type {
        case .local:
            LocalObjectStore(connector: connector, baseDirectory: localBaseDirectory)
        case .s3,
             .r2,
             .supabaseS3,
             .minio:
            S3CompatibleObjectStore(connector: connector)
        }
    }
}
