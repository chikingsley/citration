import Foundation

// MARK: - ZoteroAttachmentUploadResult

struct ZoteroAttachmentUploadResult: Sendable {
    let strategy: ZoteroAttachmentUploadStrategy
    let libraryVersion: Int64?
}

// MARK: - ZoteroAttachmentUploadStrategy

enum ZoteroAttachmentUploadStrategy: Sendable {
    case alreadyCurrent
    case directMultipart
    case directSingle
    case standard
}

// MARK: - ZoteroAttachmentUploadSource

struct ZoteroAttachmentUploadSource: Sendable {
    let fileURL: URL
    let filename: String
    let contentType: String
    let previousMD5: String?
    let digest: ZoteroAttachmentFileDigest
}

extension ZoteroAPIClient {
    func uploadAttachment(
        userID: Int64,
        itemKey: String,
        source: ZoteroAttachmentUploadSource,
        preferDirect: Bool
    ) async throws -> ZoteroAttachmentUploadResult {
        let path = "users/\(userID)/items/\(itemKey)/file"
        let condition = source.previousMD5.map { ("If-Match", $0) } ?? ("If-None-Match", "*")
        let authorization = try await attachmentAuthorization(
            path: path,
            filename: source.filename,
            contentType: source.contentType,
            digest: source.digest,
            condition: condition,
            preferDirect: preferDirect
        )
        if authorization.value.exists == 1 {
            return ZoteroAttachmentUploadResult(
                strategy: .alreadyCurrent,
                libraryVersion: authorization.libraryVersion
            )
        }
        guard let uploadKey = authorization.value.uploadKey, !uploadKey.isEmpty else {
            throw ZoteroAttachmentTransferError.invalidAuthorization
        }
        do {
            let strategy: ZoteroAttachmentUploadStrategy
            if let transfer = authorization.value.transfer {
                try await performDirectUpload(
                    transfer,
                    fileURL: source.fileURL,
                    fileSize: source.digest.size,
                    path: path,
                    uploadKey: uploadKey
                )
                strategy = transfer.kind == "multipart" ? .directMultipart : .directSingle
            } else {
                try await performStandardUpload(authorization.value, fileURL: source.fileURL)
                strategy = .standard
            }
            let registration = try await registerAttachmentUpload(
                path: path,
                uploadKey: uploadKey,
                condition: condition
            )
            return ZoteroAttachmentUploadResult(
                strategy: strategy,
                libraryVersion: registration.libraryVersion
            )
        } catch {
            if authorization.value.transfer != nil {
                _ = try? await request(
                    method: "DELETE",
                    path: "\(path)/direct/\(uploadKey)",
                    query: [],
                    body: nil,
                    headers: [:]
                )
            }
            throw error
        }
    }

    private func attachmentAuthorization(
        path: String,
        filename: String,
        contentType: String,
        digest: ZoteroAttachmentFileDigest,
        condition: (name: String, value: String),
        preferDirect: Bool
    ) async throws -> ZoteroResponse<ZoteroUploadAuthorization> {
        guard preferDirect else {
            return try await requestAttachmentAuthorization(
                path: path,
                filename: filename,
                contentType: contentType,
                digest: digest,
                condition: condition,
                direct: false
            )
        }
        do {
            return try await requestAttachmentAuthorization(
                path: path,
                filename: filename,
                contentType: contentType,
                digest: digest,
                condition: condition,
                direct: true
            )
        } catch let error as ZoteroTransportError {
            guard case let .httpStatus(status) = error, [400, 404, 503].contains(status) else {
                throw error
            }
            return try await requestAttachmentAuthorization(
                path: path,
                filename: filename,
                contentType: contentType,
                digest: digest,
                condition: condition,
                direct: false
            )
        }
    }

    private func requestAttachmentAuthorization(
        path: String,
        filename: String,
        contentType: String,
        digest: ZoteroAttachmentFileDigest,
        condition: (name: String, value: String),
        direct: Bool
    ) async throws -> ZoteroResponse<ZoteroUploadAuthorization> {
        var values = [
            "contentType": contentType,
            "filename": filename,
            "filesize": String(digest.size),
            "md5": digest.md5,
            "mtime": String(digest.modificationTimeMilliseconds),
        ]
        if direct {
            values["direct"] = "1"
        }
        let response = try await request(
            method: "POST",
            path: path,
            query: [],
            body: Self.formData(values),
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                condition.name: condition.value,
            ]
        )
        return try ZoteroResponse(
            value: JSONDecoder().decode(ZoteroUploadAuthorization.self, from: response.data),
            libraryVersion: response.libraryVersion,
            totalResults: nil
        )
    }

    private func performStandardUpload(
        _ authorization: ZoteroUploadAuthorization,
        fileURL: URL
    ) async throws {
        guard
            let url = authorization.url,
            let contentType = authorization.contentType,
            let prefix = authorization.prefix,
            let suffix = authorization.suffix,
            Self.isSafeTransferURL(url)
        else {
            throw ZoteroAttachmentTransferError.invalidAuthorization
        }
        let envelopeURL = try Self.makeUploadEnvelope(
            prefix: Data(prefix.utf8),
            fileURL: fileURL,
            suffix: Data(suffix.utf8)
        )
        defer { try? FileManager.default.removeItem(at: envelopeURL) }
        _ = try await uploadExternalFile(
            envelopeURL,
            method: "POST",
            url: url,
            headers: ["Content-Type": contentType]
        )
    }

    private func performDirectUpload(
        _ transfer: ZoteroDirectTransfer,
        fileURL: URL,
        fileSize: Int64,
        path: String,
        uploadKey: String
    ) async throws {
        let completedParts: [ZoteroCompletedPart]
        switch transfer.kind {
        case "single":
            guard let url = transfer.url, Self.isSafeTransferURL(url) else {
                throw ZoteroAttachmentTransferError.invalidAuthorization
            }
            _ = try await uploadExternalFile(fileURL, method: "PUT", url: url, headers: transfer.headers ?? [:])
            completedParts = []

        case "multipart":
            completedParts = try await uploadMultipart(transfer, fileURL: fileURL, fileSize: fileSize)

        default:
            throw ZoteroAttachmentTransferError.invalidAuthorization
        }
        let response = try await request(
            method: "POST",
            path: "\(path)/direct/\(uploadKey)/complete",
            query: [],
            body: JSONEncoder().encode(ZoteroDirectCompletion(parts: completedParts)),
            headers: ["Content-Type": "application/json"]
        )
        guard response.response.statusCode == 204 else {
            throw ZoteroAttachmentTransferError.rejectedUpload(status: response.response.statusCode)
        }
    }

    private func uploadMultipart(
        _ transfer: ZoteroDirectTransfer,
        fileURL: URL,
        fileSize: Int64
    ) async throws -> [ZoteroCompletedPart] {
        guard let partSize = transfer.partSizeBytes, partSize > 0, let parts = transfer.parts, !parts.isEmpty else {
            throw ZoteroAttachmentTransferError.invalidAuthorization
        }
        var completed = [ZoteroCompletedPart]()
        for part in parts.sorted(by: { $0.partNumber < $1.partNumber }) {
            let offset = Int64(part.partNumber - 1) * partSize
            let length = min(partSize, fileSize - offset)
            guard part.partNumber > 0, offset >= 0, length > 0, Self.isSafeTransferURL(part.url) else {
                throw ZoteroAttachmentTransferError.invalidAuthorization
            }
            let partURL = try Self.makeUploadPart(source: fileURL, offset: offset, length: length)
            defer { try? FileManager.default.removeItem(at: partURL) }
            let response = try await uploadExternalFile(
                partURL,
                method: "PUT",
                url: part.url,
                headers: part.headers
            )
            guard let etag = response.value(forHTTPHeaderField: "ETag"), !etag.isEmpty else {
                throw ZoteroAttachmentTransferError.missingResponseHeader("ETag")
            }
            completed.append(ZoteroCompletedPart(etag: etag, partNumber: part.partNumber))
        }
        return completed
    }

    private func uploadExternalFile(
        _ fileURL: URL,
        method: String,
        url: URL,
        headers: [String: String]
    ) async throws -> HTTPURLResponse {
        guard Self.isSafeTransferURL(url) else {
            throw ZoteroAttachmentTransferError.unsafeTransferURL
        }
        for attempt in 0 ..< 4 {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = method
                for (name, value) in headers {
                    request.setValue(value, forHTTPHeaderField: name)
                }
                let (_, response) = try await session.upload(for: request, fromFile: fileURL)
                guard let http = response as? HTTPURLResponse else {
                    throw ZoteroTransportError.invalidResponse
                }
                if (200 ... 299).contains(http.statusCode) {
                    return http
                }
                guard attempt < 3, http.statusCode == 429 || (500 ... 599).contains(http.statusCode) else {
                    throw ZoteroAttachmentTransferError.rejectedUpload(status: http.statusCode)
                }
            } catch let error as URLError {
                guard attempt < 3 else {
                    throw ZoteroAttachmentTransferError.networkFailure(error.errorCode)
                }
            }
            try await Task.sleep(for: .seconds(min(pow(2, Double(attempt)), 30)))
        }
        throw ZoteroTransportError.invalidResponse
    }

    private func registerAttachmentUpload(
        path: String,
        uploadKey: String,
        condition: (name: String, value: String)
    ) async throws -> RawZoteroResponse {
        try await request(
            method: "POST",
            path: path,
            query: [],
            body: Self.formData(["upload": uploadKey]),
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                condition.name: condition.value,
            ]
        )
    }

    private static func formData(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func makeUploadEnvelope(prefix: Data, fileURL: URL, suffix: Data) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "citration-upload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: destination.path, contents: prefix)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.seekToEnd()
        try copyBytes(from: fileURL, to: output)
        try output.write(contentsOf: suffix)
        return destination
    }

    private static func makeUploadPart(source: URL, offset: Int64, length: Int64) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "citration-upload-part-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        try input.seek(toOffset: UInt64(offset))
        var remaining = length
        while remaining > 0 {
            let count = Int(min(remaining, 1_048_576))
            guard let data = try input.read(upToCount: count), !data.isEmpty else {
                throw ZoteroAttachmentTransferError.fileNotAccessible
            }
            try output.write(contentsOf: data)
            remaining -= Int64(data.count)
        }
        return destination
    }

    private static func copyBytes(from source: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try output.write(contentsOf: data)
        }
    }
}

// MARK: - ZoteroUploadAuthorization

private struct ZoteroUploadAuthorization: Decodable {
    let exists: Int?
    let url: URL?
    let contentType: String?
    let prefix: String?
    let suffix: String?
    let uploadKey: String?
    let transfer: ZoteroDirectTransfer?
}

// MARK: - ZoteroDirectTransfer

private struct ZoteroDirectTransfer: Decodable {
    let kind: String
    let url: URL?
    let headers: [String: String]?
    let partSizeBytes: Int64?
    let parts: [ZoteroDirectPart]?
}

// MARK: - ZoteroDirectPart

private struct ZoteroDirectPart: Decodable {
    let partNumber: Int
    let url: URL
    let headers: [String: String]
}

// MARK: - ZoteroDirectCompletion

private struct ZoteroDirectCompletion: Encodable {
    let parts: [ZoteroCompletedPart]
}

// MARK: - ZoteroCompletedPart

private struct ZoteroCompletedPart: Encodable {
    let etag: String
    let partNumber: Int
}
