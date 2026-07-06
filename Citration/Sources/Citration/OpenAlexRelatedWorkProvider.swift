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
    private static let workSelectFields = [
        "id",
        "display_name",
        "doi",
        "publication_year",
        "type",
        "authorships",
        "primary_topic",
        "topics"
    ].joined(separator: ",")

    private let httpClient: any OpenAlexHTTPClient
    private let endpointBaseURL: URL
    private let apiKeyProvider: any OpenAlexAPIKeyProviding

    init(
        httpClient: any OpenAlexHTTPClient = URLSession.shared,
        endpointBaseURL: URL = Self.defaultEndpointBaseURL,
        apiKey: String? = nil
    ) {
        self.init(
            httpClient: httpClient,
            endpointBaseURL: endpointBaseURL,
            apiKeyProvider: StaticOpenAlexAPIKeyProvider(apiKey)
        )
    }

    init(
        httpClient: any OpenAlexHTTPClient = URLSession.shared,
        endpointBaseURL: URL = Self.defaultEndpointBaseURL,
        apiKeyProvider: any OpenAlexAPIKeyProviding
    ) {
        self.httpClient = httpClient
        self.endpointBaseURL = endpointBaseURL
        self.apiKeyProvider = apiKeyProvider
    }

    func suggestions(for item: BCItem, limit: Int) async throws -> [WorkDiscoverySuggestion] {
        guard limit > 0,
              await apiKeyProvider.apiKey() != nil,
              let doi = item.doi?.bcTrimmedNonEmpty,
              let sourceWork = try await workByDOI(doi),
              let sourceWorkID = sourceWork.shortID else {
            return []
        }

        let groups = discoveryGroups(for: sourceWork, sourceWorkID: sourceWorkID)
        return try await suggestions(
            groups: groups,
            sourceWorkID: sourceWorkID,
            limit: limit
        )
    }

    private func discoveryGroups(
        for sourceWork: OpenAlexWork,
        sourceWorkID: String
    ) -> [OpenAlexDiscoveryGroup] {
        var groups = [
            OpenAlexDiscoveryGroup(
                filter: "related_to:\(sourceWorkID)",
                reason: .openAlexRelatedWork(sourceWorkID),
                confidence: 0.72
            )
        ]

        groups.append(contentsOf: sourceWork.authorGroups)
        groups.append(contentsOf: sourceWork.institutionGroups)
        if let topicGroup = sourceWork.primaryTopicGroup {
            groups.append(topicGroup)
        }
        groups.append(OpenAlexDiscoveryGroup(filter: "cites:\(sourceWorkID)", reason: .openAlexCitedBy(sourceWorkID), confidence: 0.84))
        groups.append(OpenAlexDiscoveryGroup(filter: "cited_by:\(sourceWorkID)", reason: .openAlexReference(sourceWorkID), confidence: 0.80))
        return groups
    }

    private func suggestions(
        groups: [OpenAlexDiscoveryGroup],
        sourceWorkID: String,
        limit: Int
    ) async throws -> [WorkDiscoverySuggestion] {
        var suggestionsByID = [String: WorkDiscoverySuggestion]()
        var orderedIDs = [String]()

        for group in groups {
            let works = try await works(filter: group.filter, limit: max(2, min(limit, 5)))
            for work in works where work.shortID != sourceWorkID {
                guard let suggestion = work.discoverySuggestion(
                    providerName: name,
                    reason: group.reason,
                    confidence: group.confidence
                ) else {
                    continue
                }

                if var existing = suggestionsByID[suggestion.id] {
                    existing.confidence = max(existing.confidence, suggestion.confidence)
                    existing.reasons.append(contentsOf: suggestion.reasons.filter { !existing.reasons.contains($0) })
                    suggestionsByID[suggestion.id] = existing
                }
                else {
                    orderedIDs.append(suggestion.id)
                    suggestionsByID[suggestion.id] = suggestion
                }
            }
        }

        return orderedIDs
            .compactMap { suggestionsByID[$0] }
            .prefix(limit)
            .map { $0 }
    }

    private func workByDOI(_ doi: String) async throws -> OpenAlexWork? {
        let works = try await works(
            filter: "doi:https://doi.org/\(doi)",
            limit: 1
        )
        return works.first
    }

    private func works(filter: String, limit: Int) async throws -> [OpenAlexWork] {
        guard let url = await url(
            path: "works",
            queryItems: [
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "per-page", value: String(max(1, min(limit, 25)))),
                URLQueryItem(name: "select", value: Self.workSelectFields),
                URLQueryItem(name: "sort", value: "cited_by_count:desc")
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

    private func url(path: String, queryItems: [URLQueryItem]) async -> URL? {
        let endpointURL = endpointBaseURL.appendingPathComponent(path)
        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        var items = queryItems
        if let apiKey = await apiKeyProvider.apiKey() {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = items
        return components?.url
    }
}

private struct OpenAlexDiscoveryGroup {
    let filter: String
    let reason: RecommendationReason
    let confidence: Double
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
    let primaryTopic: OpenAlexTopic?
    let topics: [OpenAlexTopic]?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case doi
        case publicationYear = "publication_year"
        case type
        case authorships
        case primaryTopic = "primary_topic"
        case topics
    }

    var shortID: String? {
        openAlexShortID(from: id)
    }

    var authorGroups: [OpenAlexDiscoveryGroup] {
        uniqueAuthorInputs.prefix(2).map { author in
            OpenAlexDiscoveryGroup(
                filter: "author.id:\(author.id)",
                reason: .openAlexSameAuthor(author.displayName),
                confidence: 0.66
            )
        }
    }

    var institutionGroups: [OpenAlexDiscoveryGroup] {
        uniqueInstitutionInputs.prefix(2).map { institution in
            OpenAlexDiscoveryGroup(
                filter: "institutions.id:\(institution.id)",
                reason: .openAlexSameInstitution(institution.displayName),
                confidence: 0.62
            )
        }
    }

    var primaryTopicGroup: OpenAlexDiscoveryGroup? {
        guard let topic = primaryTopic?.filterInput ?? topics?.compactMap(\.filterInput).first else {
            return nil
        }

        return OpenAlexDiscoveryGroup(
            filter: "primary_topic.id:\(topic.id)",
            reason: .openAlexSameTopic(topic.displayName),
            confidence: 0.58
        )
    }

    func discoverySuggestion(
        providerName: String,
        reason: RecommendationReason,
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
            reasons: [reason]
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

    private var uniqueAuthorInputs: [OpenAlexFilterInput] {
        deduplicated((authorships ?? []).compactMap(\.author?.filterInput))
    }

    private var uniqueInstitutionInputs: [OpenAlexFilterInput] {
        deduplicated((authorships ?? []).flatMap { authorship in
            (authorship.institutions ?? []).compactMap(\.filterInput)
        })
    }

    private func deduplicated(_ inputs: [OpenAlexFilterInput]) -> [OpenAlexFilterInput] {
        var seen = Set<String>()
        return inputs.filter { input in
            seen.insert(input.id).inserted
        }
    }
}

private struct OpenAlexFilterInput {
    let id: String
    let displayName: String
}

private struct OpenAlexAuthorship: Decodable {
    let author: OpenAlexAuthor?
    let institutions: [OpenAlexInstitution]?
}

private struct OpenAlexAuthor: Decodable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }

    var filterInput: OpenAlexFilterInput? {
        guard let id = openAlexShortID(from: id),
              let displayName = displayName?.bcTrimmedNonEmpty else {
            return nil
        }
        return OpenAlexFilterInput(id: id, displayName: displayName)
    }
}

private struct OpenAlexInstitution: Decodable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }

    var filterInput: OpenAlexFilterInput? {
        guard let id = openAlexShortID(from: id),
              let displayName = displayName?.bcTrimmedNonEmpty else {
            return nil
        }
        return OpenAlexFilterInput(id: id, displayName: displayName)
    }
}

private struct OpenAlexTopic: Decodable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }

    var filterInput: OpenAlexFilterInput? {
        guard let id = openAlexShortID(from: id),
              let displayName = displayName?.bcTrimmedNonEmpty else {
            return nil
        }
        return OpenAlexFilterInput(id: id, displayName: displayName)
    }
}

private func openAlexShortID(from id: String?) -> String? {
    guard let id = id?.bcTrimmedNonEmpty else {
        return nil
    }
    return id.split(separator: "/").last.map(String.init)
}
