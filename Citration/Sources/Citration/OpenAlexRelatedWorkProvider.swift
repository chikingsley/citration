import Foundation
import CitrationCore

protocol OpenAlexHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: OpenAlexHTTPClient {}

struct OpenAlexRelatedWorkProvider: RelatedWorkDiscoveryProvider {
    let name = "openalex"

    private static let defaultEndpointBaseURL = requireEndpointURL(
        "https://api.openalex.org/",
        providerName: "OpenAlex"
    )

    private let httpClient: any OpenAlexHTTPClient
    private let endpointBaseURL: URL
    private let apiKey: String?

    init(
        httpClient: any OpenAlexHTTPClient = URLSession.shared,
        endpointBaseURL: URL = Self.defaultEndpointBaseURL,
        apiKey: String? = nil
    ) {
        self.httpClient = httpClient
        self.endpointBaseURL = endpointBaseURL
        self.apiKey = apiKey?.bcTrimmedNonEmpty
    }

    func suggestions(for item: BCItem, limit: Int) async throws -> [WorkDiscoverySuggestion] {
        guard limit > 0,
              let doi = item.doi?.bcTrimmedNonEmpty else {
            return []
        }

        guard let sourceWork = try await workByDOI(doi),
              let sourceWorkID = sourceWork.shortID else {
            return []
        }

        let relatedWorks = try await works(
            filter: "related_to:\(sourceWorkID)",
            limit: limit
        )

        return relatedWorks.compactMap { work in
            work.discoverySuggestion(
                providerName: name,
                sourceWorkID: sourceWorkID,
                confidence: 0.72
            )
        }
    }

    private func workByDOI(_ doi: String) async throws -> OpenAlexWork? {
        let works = try await works(
            filter: "doi:https://doi.org/\(doi)",
            limit: 1
        )
        return works.first
    }

    private func works(filter: String, limit: Int) async throws -> [OpenAlexWork] {
        guard let url = url(
            path: "works",
            queryItems: [
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "per-page", value: String(max(1, min(limit, 25)))),
                URLQueryItem(name: "select", value: "id,display_name,doi,publication_year,type,authorships")
            ]
        ) else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Citration/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let payload = try? JSONDecoder().decode(OpenAlexWorksEnvelope.self, from: data) else {
            return []
        }

        return payload.results
    }

    private func url(path: String, queryItems: [URLQueryItem]) -> URL? {
        let endpointURL = endpointBaseURL.appendingPathComponent(path)
        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        var items = queryItems
        if let apiKey {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = items
        return components?.url
    }
}

private struct OpenAlexWorksEnvelope: Decodable {
    let results: [OpenAlexWork]
}

private struct OpenAlexWork: Decodable {
    let id: String?
    let displayName: String?
    let doi: String?
    let publicationYear: Int?
    let type: String?
    let authorships: [OpenAlexAuthorship]?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case doi
        case publicationYear = "publication_year"
        case type
        case authorships
    }

    var shortID: String? {
        guard let id = id?.bcTrimmedNonEmpty else {
            return nil
        }
        return id.split(separator: "/").last.map(String.init)
    }

    func discoverySuggestion(
        providerName: String,
        sourceWorkID: String,
        confidence: Double
    ) -> WorkDiscoverySuggestion? {
        let title = displayName?.bcTrimmedNonEmpty
        guard let id = id?.bcTrimmedNonEmpty,
              let title else {
            return nil
        }

        return WorkDiscoverySuggestion(
            providerName: providerName,
            providerRecordID: id,
            title: title,
            creators: creators,
            publicationYear: publicationYear,
            itemType: itemType,
            identifiers: identifiers,
            sourceURL: URL(string: id),
            confidence: confidence,
            reasons: [.openAlexRelatedWork(sourceWorkID)]
        )
    }

    private var creators: [Creator] {
        (authorships ?? []).compactMap { authorship in
            guard let displayName = authorship.author?.displayName?.bcTrimmedNonEmpty else {
                return nil
            }
            return Creator(literalName: displayName)
        }
    }

    private var identifiers: [Identifier] {
        guard let doi = doi?.bcTrimmedNonEmpty else {
            return []
        }
        let rawDOI = doi
            .replacingOccurrences(of: "https://doi.org/", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "http://dx.doi.org/", with: "", options: [.caseInsensitive])
        guard let normalizedDOI = DOIParsing.normalizeCandidate(rawDOI) else {
            return []
        }
        return [Identifier(type: .doi, value: normalizedDOI)]
    }

    private var itemType: ItemType {
        switch type?.lowercased() {
        case "article", "paratext", "review":
            return .article
        case "book", "book-chapter":
            return .book
        case "preprint":
            return .preprint
        case "dissertation":
            return .thesis
        case "dataset":
            return .dataset
        default:
            return .unknown
        }
    }
}

private struct OpenAlexAuthorship: Decodable {
    let author: OpenAlexAuthor?
}

private struct OpenAlexAuthor: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}
