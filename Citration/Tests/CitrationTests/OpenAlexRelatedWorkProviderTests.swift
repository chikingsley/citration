import Foundation
import Testing
@testable import Citration
import CitrationCore

@Suite("OpenAlex Related Work Provider")
struct OpenAlexRelatedWorkProviderTests {
    @Test("fetches source work by DOI and maps related works")
    func fetchesRelatedWorksByDOI() async throws {
        let client = StubOpenAlexHTTPClient { request in
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let queryItems = components.queryItems ?? []
            let filter = queryItems.first { $0.name == "filter" }?.value
            #expect(queryItems.contains(URLQueryItem(name: "api_key", value: "test-key")))

            let payload = Self.payload(for: filter)
            let response = try Self.response(url: url, statusCode: 200)
            return (Data(payload.utf8), response)
        }

        let provider = OpenAlexRelatedWorkProvider(
            httpClient: client,
            endpointBaseURL: try #require(URL(string: "https://api.openalex.org/")),
            apiKey: "test-key"
        )
        let source = BCItem(
            title: "Source Work",
            identifiers: [Identifier(type: .doi, value: "10.5555/source")]
        )

        let suggestions = try await provider.suggestions(for: source, limit: 5)

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.providerRecordID == "https://openalex.org/W2")
        #expect(suggestions.first?.title == "Related Work")
        #expect(suggestions.first?.creators.map(\.displayName) == ["Jane Doe"])
        #expect(suggestions.first?.publicationYear == 2023)
        #expect(suggestions.first?.identifiers == [Identifier(type: .doi, value: "10.5555/related")])
        #expect(suggestions.first?.reasons == [.openAlexRelatedWork("W1")])
    }

    private static func payload(for filter: String?) -> String {
        if filter == "doi:https://doi.org/10.5555/source" {
            return sourceWorkPayload
        }

        if filter == "related_to:W1" {
            return relatedWorksPayload
        }

        return #"{"results":[]}"#
    }

    private static let sourceWorkPayload = """
    {
      "results": [
        {
          "id": "https://openalex.org/W1",
          "display_name": "Source Work",
          "doi": "https://doi.org/10.5555/source",
          "publication_year": 2024,
          "type": "article",
          "authorships": []
        }
      ]
    }
    """

    private static let relatedWorksPayload = """
    {
      "results": [
        {
          "id": "https://openalex.org/W2",
          "display_name": "Related Work",
          "doi": "https://doi.org/10.5555/related",
          "publication_year": 2023,
          "type": "article",
          "authorships": [
            { "author": { "display_name": "Jane Doe" } }
          ]
        }
      ]
    }
    """

    @Test("returns no suggestions without DOI")
    func returnsNoSuggestionsWithoutDOI() async throws {
        let client = StubOpenAlexHTTPClient { request in
            Issue.record("Unexpected OpenAlex request: \(request)")
            let url = try #require(request.url)
            let response = try Self.response(url: url, statusCode: 500)
            return (Data(), response)
        }
        let provider = OpenAlexRelatedWorkProvider(httpClient: client)

        let suggestions = try await provider.suggestions(for: BCItem(title: "Untitled"), limit: 5)

        #expect(suggestions.isEmpty)
    }

    private static func response(url: URL, statusCode: Int) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ))
    }
}

private struct StubOpenAlexHTTPClient: OpenAlexHTTPClient {
    let handler: @Sendable (URLRequest) throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
    }
}
