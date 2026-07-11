import Foundation

// MARK: - ZoteroAttachmentUploadReport

public struct ZoteroAttachmentUploadReport: Equatable, Sendable {
    public let uploadedCount: Int
    public let alreadyCurrentCount: Int
    public let directSingleCount: Int
    public let directMultipartCount: Int
    public let standardUploadCount: Int
    public let failedCount: Int
    public let latestLibraryVersion: Int64?
}

// MARK: - ZoteroAttachmentTransfer

public actor ZoteroAttachmentTransfer {
    // MARK: Lifecycle

    public init(
        database: CitrationDatabase,
        client: ZoteroAPIClient,
        attachmentsDirectory: URL,
        prefersDirectUploads: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        guard attachmentsDirectory.isFileURL else {
            throw ZoteroAttachmentTransferError.fileNotAccessible
        }
        self.database = database
        self.client = client
        self.attachmentsDirectory = attachmentsDirectory
        self.prefersDirectUploads = prefersDirectUploads
        self.fileManager = fileManager
        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
    }

    // MARK: Public

    public func download(itemKey: String) async throws -> URL {
        let context = try await libraryContext(requireWrite: false)
        guard
            let record = try database.attachmentCacheRecord(libraryID: context.libraryID, itemKey: itemKey),
            let expectedMD5 = record.remoteMD5,
            !expectedMD5.isEmpty
        else {
            throw ZoteroAttachmentTransferError.attachmentNotFound(itemKey)
        }
        if
            let localURL = record.localURL,
            record.cacheState == .downloaded,
            record.verifiedMD5 == expectedMD5,
            fileManager.fileExists(atPath: localURL.path)
        {
            return localURL
        }
        try database.markAttachmentTransferStarted(
            libraryID: context.libraryID,
            itemKey: itemKey,
            operation: "attachment-download"
        )
        do {
            let downloaded = try await client.downloadAttachment(userID: context.userID, itemKey: itemKey)
            defer { try? fileManager.removeItem(at: downloaded.temporaryURL) }
            if let responseMD5 = downloaded.responseMD5, responseMD5 != expectedMD5 {
                throw ZoteroAttachmentTransferError.hashMismatch(expected: expectedMD5, actual: responseMD5)
            }
            let digest = try await ZoteroAttachmentFileDigest.read(from: downloaded.temporaryURL)
            guard digest.md5 == expectedMD5 else {
                throw ZoteroAttachmentTransferError.hashMismatch(expected: expectedMD5, actual: digest.md5)
            }
            let destination = try installDownload(
                downloaded.temporaryURL,
                itemKey: itemKey,
                filename: record.filename,
                modificationTimeMilliseconds: downloaded.modificationTimeMilliseconds ?? record.remoteMTime
            )
            try database.markAttachmentTransferComplete(
                libraryID: context.libraryID,
                itemKey: itemKey,
                localURL: destination,
                md5: digest.md5,
                sha256: digest.sha256,
                remoteMTime: downloaded.modificationTimeMilliseconds ?? record.remoteMTime
            )
            return destination
        } catch {
            let safeError = Self.safeTransferError(error)
            try? database.markAttachmentTransferFailed(
                libraryID: context.libraryID,
                itemKey: itemKey,
                operation: "attachment-download",
                message: String(describing: safeError)
            )
            throw safeError
        }
    }

    public func uploadPending() async throws -> ZoteroAttachmentUploadReport {
        let context = try await libraryContext(requireWrite: true)
        let records = try database.pendingAttachmentUploads(libraryID: context.libraryID)
        var uploaded = 0
        var current = 0
        var directSingle = 0
        var directMultipart = 0
        var standard = 0
        var failed = 0
        var latestVersion: Int64?
        for record in records {
            do {
                let result = try await upload(record, context: context)
                switch result.strategy {
                case .alreadyCurrent:
                    current += 1

                case .directMultipart:
                    uploaded += 1
                    directMultipart += 1

                case .directSingle:
                    uploaded += 1
                    directSingle += 1

                case .standard:
                    uploaded += 1
                    standard += 1
                }
                if let version = result.libraryVersion {
                    latestVersion = max(latestVersion ?? 0, version)
                }
            } catch {
                failed += 1
                let safeError = Self.safeTransferError(error)
                try? database.markAttachmentTransferFailed(
                    libraryID: context.libraryID,
                    itemKey: record.itemKey,
                    operation: "attachment-upload",
                    message: String(describing: safeError)
                )
            }
        }
        return ZoteroAttachmentUploadReport(
            uploadedCount: uploaded,
            alreadyCurrentCount: current,
            directSingleCount: directSingle,
            directMultipartCount: directMultipart,
            standardUploadCount: standard,
            failedCount: failed,
            latestLibraryVersion: latestVersion
        )
    }

    // MARK: Private

    private let database: CitrationDatabase
    private let client: ZoteroAPIClient
    private let attachmentsDirectory: URL
    private let prefersDirectUploads: Bool
    private let fileManager: FileManager

    private static func safeTransferError(_ error: any Error) -> any Error {
        if let urlError = error as? URLError {
            return ZoteroAttachmentTransferError.networkFailure(urlError.errorCode)
        }
        return error
    }

    private func libraryContext(requireWrite: Bool) async throws -> AttachmentLibraryContext {
        let keyInfo = try await client.keyInfo()
        guard keyInfo.canAccessUserFiles else {
            throw ZoteroTransportError.keyCannotAccessFiles
        }
        if requireWrite, !keyInfo.canWriteUserLibrary {
            throw ZoteroTransportError.keyCannotWriteLibrary
        }
        let identity = ZoteroLibraryIdentity(type: "user", remoteID: keyInfo.userID)
        let libraryID = try database.upsertLibrary(identity: identity, name: keyInfo.displayName)
        return AttachmentLibraryContext(userID: keyInfo.userID, libraryID: libraryID)
    }

    private func upload(
        _ record: ZoteroAttachmentCacheRecord,
        context: AttachmentLibraryContext
    ) async throws -> ZoteroAttachmentUploadResult {
        guard let localURL = record.localURL, fileManager.fileExists(atPath: localURL.path) else {
            throw ZoteroAttachmentTransferError.fileNotAccessible
        }
        let digest = try await ZoteroAttachmentFileDigest.read(from: localURL)
        if record.remoteMD5 == digest.md5 {
            try database.markAttachmentTransferComplete(
                libraryID: context.libraryID,
                itemKey: record.itemKey,
                localURL: localURL,
                md5: digest.md5,
                sha256: digest.sha256,
                remoteMTime: record.remoteMTime ?? digest.modificationTimeMilliseconds
            )
            return ZoteroAttachmentUploadResult(strategy: .alreadyCurrent, libraryVersion: nil)
        }
        try database.markAttachmentTransferStarted(
            libraryID: context.libraryID,
            itemKey: record.itemKey,
            operation: "attachment-upload"
        )
        let result = try await client.uploadAttachment(
            userID: context.userID,
            itemKey: record.itemKey,
            source: ZoteroAttachmentUploadSource(
                fileURL: localURL,
                filename: record.filename,
                contentType: record.contentType,
                previousMD5: record.remoteMD5,
                digest: digest
            ),
            preferDirect: prefersDirectUploads
        )
        try database.markAttachmentTransferComplete(
            libraryID: context.libraryID,
            itemKey: record.itemKey,
            localURL: localURL,
            md5: digest.md5,
            sha256: digest.sha256,
            remoteMTime: digest.modificationTimeMilliseconds
        )
        return result
    }

    private func installDownload(
        _ source: URL,
        itemKey: String,
        filename: String,
        modificationTimeMilliseconds: Int64?
    ) throws -> URL {
        let safeName = URL(filePath: filename).lastPathComponent
        guard !safeName.isEmpty, safeName != ".", safeName != ".." else {
            throw ZoteroAttachmentTransferError.fileNotAccessible
        }
        let directory = attachmentsDirectory.appending(path: itemKey, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: safeName)
        let staging = directory.appending(path: ".incoming-\(UUID().uuidString)")
        try fileManager.copyItem(at: source, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        if let milliseconds = modificationTimeMilliseconds {
            try fileManager.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(milliseconds) / 1000)],
                ofItemAtPath: destination.path
            )
        }
        return destination
    }
}

// MARK: - AttachmentLibraryContext

private struct AttachmentLibraryContext {
    let userID: Int64
    let libraryID: Int64
}
