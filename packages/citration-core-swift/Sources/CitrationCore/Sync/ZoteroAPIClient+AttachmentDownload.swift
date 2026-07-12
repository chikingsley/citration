import Foundation

// MARK: - ZoteroDownloadedAttachment

struct ZoteroDownloadedAttachment: Sendable {
    let temporaryURL: URL
    let responseMD5: String?
    let modificationTimeMilliseconds: Int64?
}

extension ZoteroAPIClient {
    func downloadAttachment(
        userID: Int64,
        itemKey: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ZoteroDownloadedAttachment {
        let endpoint = connection.serverURL.appending(path: "users/\(userID)/items/\(itemKey)/file")
        var request = URLRequest(url: endpoint)
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.setValue(connection.apiKey, forHTTPHeaderField: "Zotero-API-Key")
        request.setValue("Citration/1", forHTTPHeaderField: "User-Agent")

        let (initialURL, initialResponse) = try await session.download(
            for: request,
            delegate: ZoteroAttachmentDownloadDelegate(allowsRedirects: false, progress: progress)
        )
        guard let initialHTTP = initialResponse as? HTTPURLResponse else {
            throw ZoteroAttachmentTransferError.invalidDownloadResponse
        }
        let initialMD5 = Self.attachmentMD5(from: initialHTTP)
        let initialMTime = Self.attachmentMTime(from: initialHTTP)
        if (200 ... 299).contains(initialHTTP.statusCode) {
            return try Self.retainDownload(
                initialURL,
                responseMD5: initialMD5,
                modificationTimeMilliseconds: initialMTime
            )
        }
        guard
            (300 ... 399).contains(initialHTTP.statusCode),
            let location = initialHTTP.value(forHTTPHeaderField: "Location"),
            let redirectURL = URL(string: location, relativeTo: endpoint)?.absoluteURL,
            Self.isSafeTransferURL(redirectURL)
        else {
            throw ZoteroAttachmentTransferError.invalidDownloadResponse
        }

        let (downloadURL, response) = try await session.download(
            from: redirectURL,
            delegate: ZoteroAttachmentDownloadDelegate(allowsRedirects: true, progress: progress)
        )
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw ZoteroAttachmentTransferError.invalidDownloadResponse
        }
        return try Self.retainDownload(
            downloadURL,
            responseMD5: initialMD5 ?? Self.attachmentMD5(from: http),
            modificationTimeMilliseconds: initialMTime ?? Self.attachmentMTime(from: http)
        )
    }

    static func isSafeTransferURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        if components.scheme?.lowercased() == "https" {
            return components.host != nil
        }
        let host = components.host?.lowercased()
        return components.scheme?.lowercased() == "http"
            && (host == "localhost" || host == "127.0.0.1" || host == "::1")
    }

    private static func retainDownload(
        _ source: URL,
        responseMD5: String?,
        modificationTimeMilliseconds: Int64?
    ) throws -> ZoteroDownloadedAttachment {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "citration-download-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: source, to: destination)
        return ZoteroDownloadedAttachment(
            temporaryURL: destination,
            responseMD5: responseMD5,
            modificationTimeMilliseconds: modificationTimeMilliseconds
        )
    }

    private static func attachmentMD5(from response: HTTPURLResponse) -> String? {
        let value = response.value(forHTTPHeaderField: "Zotero-File-MD5")
            ?? response.value(forHTTPHeaderField: "ETag")
        return value?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func attachmentMTime(from response: HTTPURLResponse) -> Int64? {
        response.value(forHTTPHeaderField: "Zotero-File-Modification-Time").flatMap(Int64.init)
    }
}

// MARK: - ZoteroAttachmentDownloadDelegate

private final class ZoteroAttachmentDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    init(allowsRedirects: Bool, progress: (@Sendable (Double) -> Void)?) {
        self.allowsRedirects = allowsRedirects
        self.progress = progress
    }

    // MARK: Internal

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(allowsRedirects ? newRequest : nil)
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }
        progress?(min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1))
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo _: URL
    ) {}

    // MARK: Private

    private let allowsRedirects: Bool
    private let progress: (@Sendable (Double) -> Void)?
}
