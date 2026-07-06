import Foundation
import Testing
@testable import Citration
import CitrationCore

@Suite("OpenAlex Related Work Provider")
struct OpenAlexRelatedWorkProviderTests {
    @Test("fetches source work by DOI and maps graph suggestions")
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

        let suggestions = try await provider.suggestions(for: source, limit: 8)

        #expect(suggestions.count == 6)
        assertSuggestion(
            suggestions,
            title: "Related Work",
            reasons: [.openAlexRelatedWork("W1")]
        )
        assertSuggestion(
            suggestions,
            title: "Same Author Work",
            reasons: [.openAlexSameAuthor("Source Author")]
        )
        assertSuggestion(
            suggestions,
            title: "Same Institution Work",
            reasons: [.openAlexSameInstitution("Source Lab")]
        )
        assertSuggestion(
            suggestions,
            title: "Same Topic Work",
            reasons: [.openAlexSameTopic("Bibliometrics")]
        )
        assertSuggestion(
            suggestions,
            title: "Citing Work",
            reasons: [.openAlexCitedBy("W1")]
        )
        assertSuggestion(
            suggestions,
            title: "Reference Work",
            reasons: [.openAlexReference("W1")]
        )
    }

    private static func payload(for filter: String?) -> String {
        if filter == "doi:https://doi.org/10.5555/source" {
            return sourceWorkPayload
        }

        if filter == "related_to:W1" {
            return relatedWorksPayload
        }

        if filter == "author.id:A1" {
            return worksPayload(id: "W3", title: "Same Author Work")
        }

        if filter == "institutions.id:I1" {
            return worksPayload(id: "W4", title: "Same Institution Work")
        }

        if filter == "primary_topic.id:T1" {
            return worksPayload(id: "W5", title: "Same Topic Work")
        }

        if filter == "cites:W1" {
            return worksPayload(id: "W6", title: "Citing Work")
        }

        if filter == "cited_by:W1" {
            return worksPayload(id: "W7", title: "Reference Work")
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
          "authorships": [
            {
              "author": {
                "id": "https://openalex.org/A1",
                "display_name": "Source Author"
              },
              "institutions": [
                {
                  "id": "https://openalex.org/I1",
                  "display_name": "Source Lab"
                }
              ]
            }
          ],
          "primary_topic": {
            "id": "https://openalex.org/T1",
            "display_name": "Bibliometrics"
          }
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

    private static func worksPayload(id: String, title: String) -> String {
        """
        {
          "results": [
            {
              "id": "https://openalex.org/\(id)",
              "display_name": "\(title)",
              "doi": null,
              "publication_year": 2022,
              "type": "article",
              "authorships": []
            }
          ]
        }
        """
    }

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

    @Test("returns no suggestions without API key")
    func returnsNoSuggestionsWithoutAPIKey() async throws {
        let client = StubOpenAlexHTTPClient { request in
            Issue.record("Unexpected OpenAlex request: \(request)")
            let url = try #require(request.url)
            let response = try Self.response(url: url, statusCode: 500)
            return (Data(), response)
        }
        let provider = OpenAlexRelatedWorkProvider(httpClient: client)
        let source = BCItem(
            title: "Source Work",
            identifiers: [Identifier(type: .doi, value: "10.5555/source")]
        )

        let suggestions = try await provider.suggestions(for: source, limit: 5)

        #expect(suggestions.isEmpty)
    }

    private func assertSuggestion(
        _ suggestions: [WorkDiscoverySuggestion],
        title: String,
        reasons: [RecommendationReason]
    ) {
        let suggestion = suggestions.first { $0.title == title }
        #expect(suggestion?.reasons == reasons)
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
