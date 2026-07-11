import Foundation

// MARK: - ZoteroResponse

public struct ZoteroResponse<Value: Sendable>: Sendable {
    public let value: Value
    public let libraryVersion: Int64?
    public let totalResults: Int?
}

// MARK: - ZoteroDeletedObjects

public struct ZoteroDeletedObjects: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        collections: [String] = [],
        items: [String] = [],
        searches: [String] = [],
        settings: [String] = [],
        tags: [String] = []
    ) {
        self.collections = collections
        self.items = items
        self.searches = searches
        self.settings = settings
        self.tags = tags
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collections = try container.decodeIfPresent([String].self, forKey: .collections) ?? []
        items = try container.decodeIfPresent([String].self, forKey: .items) ?? []
        searches = try container.decodeIfPresent([String].self, forKey: .searches) ?? []
        settings = try container.decodeIfPresent([String].self, forKey: .settings) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    // MARK: Public

    public let collections: [String]
    public let items: [String]
    public let searches: [String]
    public let settings: [String]
    public let tags: [String]
}

// MARK: - ZoteroAPIClient

public actor ZoteroAPIClient {
    // MARK: Lifecycle

    public init(connection: ZoteroConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    // MARK: Public

    public func keyInfo() async throws -> ZoteroKeyInfo {
        let response: ZoteroResponse<ZoteroKeyInfo> = try await get(path: "keys/current")
        guard response.value.canReadUserLibrary else {
            throw ZoteroTransportError.keyCannotReadLibrary
        }
        return response.value
    }

    public func versions(
        path: String,
        since: Int64,
        extraQuery: [URLQueryItem] = []
    ) async throws -> ZoteroResponse<[String: Int64]> {
        var versions = [String: Int64]()
        var latestVersion: Int64?
        var start = 0
        var total = 0
        repeat {
            var query = [
                URLQueryItem(name: "format", value: "versions"),
                URLQueryItem(name: "since", value: String(since)),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "start", value: String(start)),
            ]
            query.append(contentsOf: extraQuery)
            let page: ZoteroResponse<[String: Int64]> = try await get(path: path, query: query)
            versions.merge(page.value, uniquingKeysWith: max)
            latestVersion = max(latestVersion ?? 0, page.libraryVersion ?? 0)
            start += page.value.count
            total = page.totalResults ?? start
            if page.value.isEmpty {
                break
            }
        } while start < total
        return ZoteroResponse(value: versions, libraryVersion: latestVersion, totalResults: total)
    }

    public func objects(
        path: String,
        keyParameter: String,
        keys: [String],
        extraQuery: [URLQueryItem] = []
    ) async throws -> ZoteroResponse<[ZoteroRawObject]> {
        var objects = [ZoteroRawObject]()
        var latestVersion: Int64?
        for batch in keys.chunked(maxCount: 50) {
            var query = [URLQueryItem(name: keyParameter, value: batch.joined(separator: ","))]
            query.append(contentsOf: extraQuery)
            let response: ZoteroResponse<[ZoteroRawObject]> = try await get(path: path, query: query)
            objects.append(contentsOf: response.value)
            latestVersion = max(latestVersion ?? 0, response.libraryVersion ?? 0)
        }
        return ZoteroResponse(value: objects, libraryVersion: latestVersion, totalResults: objects.count)
    }

    public func settings(userID: Int64, since: Int64) async throws -> ZoteroResponse<JSONValue> {
        try await get(
            path: "users/\(userID)/settings",
            query: [URLQueryItem(name: "since", value: String(since))]
        )
    }

    public func deleted(userID: Int64, since: Int64) async throws -> ZoteroResponse<ZoteroDeletedObjects> {
        try await get(
            path: "users/\(userID)/deleted",
            query: [URLQueryItem(name: "since", value: String(since))]
        )
    }

    public func fullTextVersions(userID: Int64, since: Int64) async throws -> ZoteroResponse<[String: Int64]> {
        try await get(
            path: "users/\(userID)/fulltext",
            query: [URLQueryItem(name: "since", value: String(since))]
        )
    }

    public func fullText(userID: Int64, itemKey: String) async throws -> ZoteroResponse<JSONValue> {
        try await get(path: "users/\(userID)/items/\(itemKey)/fulltext")
    }

    public func groups(userID: Int64) async throws -> ZoteroResponse<[JSONValue]> {
        try await get(path: "users/\(userID)/groups")
    }

    public func get<Value: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> ZoteroResponse<Value> {
        let response = try await request(path: path, query: query)
        return try ZoteroResponse(
            value: JSONDecoder().decode(Value.self, from: response.data),
            libraryVersion: response.libraryVersion,
            totalResults: response.totalResults
        )
    }

    // MARK: Private

    private let connection: ZoteroConnection
    private let session: URLSession
    private var notBefore: Date = .distantPast

    private func request(
        path: String,
        query: [URLQueryItem]
    ) async throws -> RawZoteroResponse {
        let url = try requestURL(path: path, query: query)
        for attempt in 0 ..< 4 {
            try await waitForBackoff()
            var request = URLRequest(url: url)
            request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
            request.setValue(connection.apiKey, forHTTPHeaderField: "Zotero-API-Key")
            request.setValue("Citration/1", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ZoteroTransportError.invalidResponse
            }
            applyBackoff(from: http)
            if (200 ... 299).contains(http.statusCode) {
                return try RawZoteroResponse(data: data, response: http)
            }
            guard attempt < 3, http.statusCode == 429 || (500 ... 599).contains(http.statusCode) else {
                throw ZoteroTransportError.httpStatus(http.statusCode)
            }
            let seconds = retryDelay(response: http, attempt: attempt)
            notBefore = max(notBefore, Date().addingTimeInterval(seconds))
        }
        throw ZoteroTransportError.invalidResponse
    }

    private func requestURL(path: String, query: [URLQueryItem]) throws -> URL {
        let url = connection.serverURL.appending(path: path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ZoteroTransportError.invalidServerURL
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let result = components.url else {
            throw ZoteroTransportError.invalidServerURL
        }
        return result
    }

    private func waitForBackoff() async throws {
        let delay = notBefore.timeIntervalSinceNow
        if delay > 0 {
            try await Task.sleep(for: .milliseconds(Int64((delay * 1000).rounded(.up))))
        }
    }

    private func applyBackoff(from response: HTTPURLResponse) {
        guard
            let value = response.value(forHTTPHeaderField: "Backoff"),
            let seconds = TimeInterval(value),
            seconds > 0
        else {
            return
        }
        notBefore = max(notBefore, Date().addingTimeInterval(min(seconds, 300)))
    }

    private func retryDelay(response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if
            let value = response.value(forHTTPHeaderField: "Retry-After"),
            let seconds = TimeInterval(value),
            seconds > 0
        {
            return min(seconds, 300)
        }
        return min(pow(2, Double(attempt)), 30)
    }
}

// MARK: - RawZoteroResponse

private struct RawZoteroResponse {
    // MARK: Lifecycle

    init(data: Data, response: HTTPURLResponse) throws {
        self.data = data
        libraryVersion = try Self.integerHeader("Last-Modified-Version", response: response)
        totalResults = try Self.integerHeader("Total-Results", response: response).map(Int.init)
    }

    // MARK: Internal

    let data: Data
    let libraryVersion: Int64?
    let totalResults: Int?

    // MARK: Private

    private static func integerHeader(
        _ name: String,
        response: HTTPURLResponse
    ) throws -> Int64? {
        guard let value = response.value(forHTTPHeaderField: name) else {
            return nil
        }
        guard let result = Int64(value) else {
            throw ZoteroTransportError.invalidHeader(name, value: value)
        }
        return result
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else {
            return []
        }
        return stride(from: 0, to: count, by: maxCount).map { start in
            Array(self[start ..< Swift.min(start + maxCount, count)])
        }
    }
}
