import Foundation

// MARK: - ZoteroDownloadedAttachment

struct ZoteroDownloadedAttachment: Sendable {
    let temporaryURL: URL
    let responseMD5: String?
    let modificationTimeMilliseconds: Int64?
}

extension ZoteroAPIClient {
    func downloadAttachment(userID: Int64, itemKey: String) async throws -> ZoteroDownloadedAttachment {
        let endpoint = connection.serverURL.appending(path: "users/\(userID)/items/\(itemKey)/file")
        var request = URLRequest(url: endpoint)
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.setValue(connection.apiKey, forHTTPHeaderField: "Zotero-API-Key")
        request.setValue("Citration/1", forHTTPHeaderField: "User-Agent")

        let (initialURL, initialResponse) = try await session.download(
            for: request,
            delegate: ZoteroNoRedirectDelegate()
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

        let (downloadURL, response) = try await session.download(from: redirectURL)
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

// MARK: - ZoteroNoRedirectDelegate

private final class ZoteroNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
