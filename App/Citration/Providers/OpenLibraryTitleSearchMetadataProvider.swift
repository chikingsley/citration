import CitrationCore
import Foundation

// MARK: - OpenLibraryTitleSearchMetadataProvider

/// Resolves books by title through OpenLibrary's search API — the
/// path that finds pre-ISBN works (e.g. OCR-titled scans) that
/// identifier-based providers can never reach.
struct OpenLibraryTitleSearchMetadataProvider: MetadataProvider {
    // MARK: Lifecycle

    init(
        session: URLSession = .shared,
        endpointURL: URL = Self.defaultEndpointURL
    ) {
        self.session = session
        self.endpointURL = endpointURL
    }

    // MARK: Internal

    let name: String = "openlibrary-title"

    static func records(
        fromSearchData data: Data,
        query: String,
        providerName: String
    ) -> [CanonicalMetadataRecord] {
        guard let payload = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
            return []
        }

        for doc in payload.docs.prefix(5) {
            guard
                let title = doc.title.bcTrimmedNonEmpty,
                TitleSimilarity.isAcceptableMatch(query: query, candidate: title)
            else {
                continue
            }

            var identifiers = [Identifier]()
            if let isbn = doc.isbn?.compactMap(ISBNParsing.normalizeCandidate).first {
                identifiers.append(Identifier(type: .isbn, value: isbn))
            }

            let creators = (doc.authorName ?? []).compactMap { name -> Creator? in
                guard let literal = name.bcTrimmedNonEmpty else {
                    return nil
                }
                return Creator(literalName: literal)
            }

            let record = CanonicalMetadataRecord(
                title: title,
                creators: creators,
                publicationYear: doc.firstPublishYear,
                itemType: .book,
                identifiers: identifiers,
                confidence: 0.65,
                provenance: MetadataProvenance(
                    providerName: providerName,
                    sourceRecordID: doc.key,
                    fieldSources: [
                        "title": "openlibrary.title",
                        "publicationYear": "openlibrary.first_publish_year",
                        "creators": "openlibrary.author_name",
                    ]
                ),
                rawPayload: data
            )
            return [record]
        }

        return []
    }

    func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord] {
        guard let query = request.freeTextQuery?.bcTrimmedNonEmpty else {
            return []
        }

        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: query),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,isbn"),
        ]

        guard let url = components?.url else {
            return []
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 12
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Citration/1.0 (mailto:support@citration.app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: urlRequest)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200 ..< 300).contains(httpResponse.statusCode)
        else {
            return []
        }

        return Self.records(fromSearchData: data, query: query, providerName: name)
    }

    // MARK: Private

    private static let defaultEndpointURL = requireEndpointURL(
        "https://openlibrary.org/search.json",
        providerName: "OpenLibrary title search"
    )

    private let session: URLSession
    private let endpointURL: URL
}

// MARK: - SearchResponse

private struct SearchResponse: Decodable {
    let docs: [SearchDoc]
}

// MARK: - SearchDoc

private struct SearchDoc: Decodable {
    enum CodingKeys: String, CodingKey {
        case key
        case title
        case authorName = "author_name"
        case firstPublishYear = "first_publish_year"
        case isbn
    }

    let key: String?
    let title: String
    let authorName: [String]?
    let firstPublishYear: Int?
    let isbn: [String]?
}
