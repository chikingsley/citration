import CitrationCore
import CryptoKit
import Foundation

// MARK: - OCRServicing

protocol OCRServicing: Sendable {
    func isConfigured() async -> Bool

    /// Returns the document's recognized text as markdown, one section
    /// per page. Results are cached by content hash, so repeat calls
    /// for the same bytes never hit the network again.
    func recognizeText(from documentURL: URL) async throws -> String
}

// MARK: - OCRServiceError

enum OCRServiceError: Error {
    case notConfigured
    case unreadableDocument
    case requestFailed(String)
}

// MARK: - OCRResultCache

/// Stores OCR output on disk keyed by the SHA-256 of the document
/// bytes, so a rerun of the same file is free.
struct OCRResultCache {
    // MARK: Lifecycle

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    // MARK: Internal

    static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func load(contentHash: String) -> String? {
        guard let directory else {
            return nil
        }
        let fileURL = directory.appendingPathComponent("\(contentHash).md")
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func store(_ text: String, contentHash: String) {
        guard let directory else {
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(contentHash).md")
        try? Data(text.utf8).write(to: fileURL, options: [.atomic])
    }

    // MARK: Private

    private let directory: URL?

    private static func defaultDirectory() -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Citration", isDirectory: true)
            .appendingPathComponent("ocr", isDirectory: true)
    }
}

// MARK: - MistralOCRService

/// OCR via Mistral's document API: upload the file, request a signed
/// URL, and run the `mistral-ocr-latest` model over it.
actor MistralOCRService: OCRServicing {
    // MARK: Lifecycle

    init(
        keyStore: any APIKeyStore = FileAPIKeyStore(fileName: "mistral-api-key"),
        cache: OCRResultCache = OCRResultCache(),
        session: URLSession = .shared
    ) {
        self.keyStore = keyStore
        self.cache = cache
        self.session = session
    }

    // MARK: Internal

    func isConfigured() async -> Bool {
        await apiKey() != nil
    }

    func recognizeText(from documentURL: URL) async throws -> String {
        guard let data = try? Data(contentsOf: documentURL) else {
            throw OCRServiceError.unreadableDocument
        }

        let contentHash = OCRResultCache.contentHash(of: data)
        if let cached = cache.load(contentHash: contentHash) {
            return cached
        }

        guard let apiKey = await apiKey() else {
            throw OCRServiceError.notConfigured
        }

        let fileID = try await uploadFile(data, name: documentURL.lastPathComponent, apiKey: apiKey)
        let signedURL = try await signedURL(forFileID: fileID, apiKey: apiKey)
        let pages = try await runOCR(documentURL: signedURL, apiKey: apiKey)

        let combined = pages
            .map { "<!-- page \($0.index + 1) -->\n\n\($0.markdown.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n\n---\n\n") + "\n"

        cache.store(combined, contentHash: contentHash)
        return combined
    }

    // MARK: Private

    private struct UploadResponse: Decodable {
        let id: String
    }

    private struct SignedURLResponse: Decodable {
        let url: String
    }

    private struct OCRResponse: Decodable {
        struct Page: Decodable {
            let index: Int
            let markdown: String
        }

        let pages: [Page]
    }

    private static let model = "mistral-ocr-latest"

    private static var apiBase: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.mistral.ai"
        components.path = "/v1"
        guard let url = components.url else {
            fatalError("Invalid Mistral API base URL")
        }
        return url
    }

    private let keyStore: any APIKeyStore
    private let cache: OCRResultCache
    private let session: URLSession

    private func apiKey() async -> String? {
        if let stored = await keyStore.loadAPIKey() {
            return stored
        }
        return ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]?.bcTrimmedNonEmpty
    }

    private func uploadFile(_ data: Data, name: String, apiKey: String) async throws -> String {
        let boundary = "citration-\(UUID().uuidString)"
        var request = URLRequest(url: Self.apiBase.appendingPathComponent("files"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"purpose\"\r\n\r\nocr\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".utf8))
        body.append(Data("Content-Type: application/pdf\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let response: UploadResponse = try await send(request)
        return response.id
    }

    private func signedURL(forFileID fileID: String, apiKey: String) async throws -> String {
        var components = URLComponents(
            url: Self.apiBase.appendingPathComponent("files/\(fileID)/url"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "expiry", value: "1")]
        guard let url = components?.url else {
            throw OCRServiceError.requestFailed("Invalid signed URL request")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let response: SignedURLResponse = try await send(request)
        return response.url
    }

    private func runOCR(documentURL: String, apiKey: String) async throws -> [OCRResponse.Page] {
        var request = URLRequest(url: Self.apiBase.appendingPathComponent("ocr"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let payload: [String: Any] = [
            "model": Self.model,
            "document": ["type": "document_url", "document_url": documentURL],
            "include_image_base64": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let response: OCRResponse = try await send(request)
        return response.pages
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, urlResponse) = try await session.data(for: request)
        guard
            let http = urlResponse as? HTTPURLResponse,
            (200 ..< 300).contains(http.statusCode)
        else {
            let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
            let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw OCRServiceError.requestFailed("HTTP \(status): \(bodyPreview)")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
