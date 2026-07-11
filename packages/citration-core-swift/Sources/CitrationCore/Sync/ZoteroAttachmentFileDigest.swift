import CryptoKit
import Foundation

// MARK: - ZoteroAttachmentTransferError

public enum ZoteroAttachmentTransferError: Error, Equatable, Sendable {
    case attachmentNotFound(String)
    case fileNotAccessible
    case hashMismatch(expected: String, actual: String)
    case invalidAuthorization
    case invalidDownloadResponse
    case missingResponseHeader(String)
    case networkFailure(Int)
    case rejectedUpload(status: Int)
    case unsafeTransferURL
}

// MARK: - ZoteroAttachmentFileDigest

struct ZoteroAttachmentFileDigest: Equatable, Sendable {
    let md5: String
    let sha256: String
    let size: Int64
    let modificationTimeMilliseconds: Int64

    static func read(from url: URL) async throws -> Self {
        try await Task.detached(priority: .utility) {
            guard url.isFileURL else {
                throw ZoteroAttachmentTransferError.fileNotAccessible
            }
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .contentModificationDateKey,
            ])
            guard values.isRegularFile == true, let size = values.fileSize else {
                throw ZoteroAttachmentTransferError.fileNotAccessible
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var md5 = Insecure.MD5()
            var sha256 = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                md5.update(data: data)
                sha256.update(data: data)
            }
            let modificationDate = values.contentModificationDate ?? .now
            return Self(
                md5: md5.finalize().hexString,
                sha256: sha256.finalize().hexString,
                size: Int64(size),
                modificationTimeMilliseconds: Int64((modificationDate.timeIntervalSince1970 * 1000).rounded())
            )
        }.value
    }
}

private extension Sequence<UInt8> {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
