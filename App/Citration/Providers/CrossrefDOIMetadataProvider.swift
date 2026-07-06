import CitrationCore
import Foundation

// MARK: - CrossrefDOIMetadataProvider

struct CrossrefDOIMetadataProvider: MetadataProvider {
    // MARK: Lifecycle

    init(
        session: URLSession = .shared,
        endpointBaseURL: URL = Self.defaultEndpointBaseURL
    ) {
        self.session = session
        self.endpointBaseURL = endpointBaseURL
    }

    // MARK: Internal

    let name: String = "crossref-doi"

    func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord] {
        if
            let rawDOI = request.identifiers.first(where: { $0.type == .doi })?.value,
            let doi = DOIParsing.normalizeCandidate(rawDOI)
        {
            return try await resolveByDOI(doi)
        }

        if let query = request.freeTextQuery?.bcTrimmedNonEmpty {
            return try await resolveByTitle(query)
        }

        return []
    }

    // MARK: Private

    private static let defaultEndpointBaseURL = requireEndpointURL(
        "https://api.crossref.org/works/",
        providerName: "Crossref DOI"
    )

    private let session: URLSession
    private let endpointBaseURL: URL

    private func resolveByDOI(_ doi: String) async throws -> [CanonicalMetadataRecord] {
        guard
            let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: encodedDOI, relativeTo: endpointBaseURL)
        else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Citration/1.0 (mailto:support@citration.app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200 ..< 300).contains(httpResponse.statusCode),
            let message = try? JSONDecoder().decode(CrossrefEnvelope.self, from: data).message
        else {
            return []
        }

        let record = makeRecord(
            from: message,
            fallbackDOI: doi,
            confidence: 0.99
        )

        return [record]
    }

    private func resolveByTitle(_ query: String) async throws -> [CanonicalMetadataRecord] {
        guard let worksURL = URL(string: "https://api.crossref.org/works") else {
            return []
        }

        var components = URLComponents(url: worksURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query.bibliographic", value: query),
            URLQueryItem(name: "rows", value: "1"),
        ]

        guard let url = components?.url else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Citration/1.0 (mailto:support@citration.app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200 ..< 300).contains(httpResponse.statusCode),
            let search = try? JSONDecoder().decode(CrossrefSearchEnvelope.self, from: data),
            let message = search.message.items.first
        else {
            return []
        }

        // Crossref always returns its best guess; only trust it when the
        // returned title genuinely resembles what was asked for.
        let candidateTitle = message.title.compactMap(\.bcTrimmedNonEmpty).first ?? ""
        guard TitleSimilarity.isAcceptableMatch(query: query, candidate: candidateTitle) else {
            return []
        }

        let record = makeRecord(
            from: message,
            fallbackDOI: nil,
            confidence: 0.7
        )

        return [record]
    }

    private func makeRecord(
        from message: CrossrefMessage,
        fallbackDOI: String?,
        confidence: Double
    ) -> CanonicalMetadataRecord {
        let title = message.title.compactMap(\.bcTrimmedNonEmpty).first
        let creators = normalizedCreators(from: message.author)
        let publicationYear = message.publicationYear
        let itemType = mapItemType(message.type)
        let sourceURL = URL(string: message.url ?? "")

        let canonicalDOI = DOIParsing.normalizeCandidate(message.doi ?? "") ?? fallbackDOI
        let canonicalTitle = title ?? canonicalDOI.map { "DOI \($0)" } ?? "Imported record"

        var identifiers = [Identifier]()
        if let canonicalDOI {
            identifiers.append(Identifier(type: .doi, value: canonicalDOI))
        }

        return CanonicalMetadataRecord(
            title: canonicalTitle,
            creators: creators,
            publicationYear: publicationYear,
            itemType: itemType,
            identifiers: identifiers,
            abstract: message.abstract?.bcTrimmedNonEmpty,
            sourceURL: sourceURL,
            confidence: confidence,
            provenance: MetadataProvenance(
                providerName: name,
                sourceRecordID: canonicalDOI ?? canonicalTitle,
                fieldSources: [
                    "title": "crossref.message.title",
                    "creators": "crossref.message.author",
                    "publicationYear": "crossref.message.issued|published-*",
                ]
            ),
            rawPayload: nil
        )
    }

    private func normalizedCreators(from authors: [CrossrefAuthor]) -> [Creator] {
        authors.compactMap { author in
            let given = author.given?.bcTrimmedNonEmpty
            let family = author.family?.bcTrimmedNonEmpty
            let literal = author.name?.bcTrimmedNonEmpty

            if given == nil, family == nil, literal == nil {
                return nil
            }

            return Creator(givenName: given, familyName: family, literalName: literal)
        }
    }

    private func mapItemType(_ rawType: String?) -> ItemType {
        switch rawType?.lowercased() {
        case "journal-article",
             "proceedings-article",
             "reference-entry":
            .article
        case "book",
             "book-chapter",
             "book-part":
            .book
        case "posted-content":
            .preprint
        case "dissertation":
            .thesis
        case "dataset":
            .dataset
        case "report",
             "standard":
            .webpage
        default:
            .unknown
        }
    }
}

// MARK: - CrossrefEnvelope

private struct CrossrefEnvelope: Decodable {
    let message: CrossrefMessage
}

// MARK: - CrossrefSearchEnvelope

private struct CrossrefSearchEnvelope: Decodable {
    let message: CrossrefSearchMessage
}

// MARK: - CrossrefSearchMessage

private struct CrossrefSearchMessage: Decodable {
    let items: [CrossrefMessage]
}

// MARK: - CrossrefMessage

private struct CrossrefMessage: Decodable {
    enum CodingKeys: String, CodingKey {
        case doi = "DOI"
        case title
        case author
        case type
        case abstract
        case url = "URL"
        case issued
        case publishedPrint = "published-print"
        case publishedOnline = "published-online"
        case created
    }

    let doi: String?
    let title: [String]
    let author: [CrossrefAuthor]
    let type: String?
    let abstract: String?
    let url: String?
    let issued: CrossrefDateParts?
    let publishedPrint: CrossrefDateParts?
    let publishedOnline: CrossrefDateParts?
    let created: CrossrefDateParts?

    var publicationYear: Int? {
        publishedPrint?.firstYear
            ?? publishedOnline?.firstYear
            ?? issued?.firstYear
            ?? created?.firstYear
    }
}

// MARK: - CrossrefAuthor

private struct CrossrefAuthor: Decodable {
    let given: String?
    let family: String?
    let name: String?
}

// MARK: - CrossrefDateParts

private struct CrossrefDateParts: Decodable {
    enum CodingKeys: String, CodingKey {
        case dateParts = "date-parts"
    }

    let dateParts: [[Int]]

    var firstYear: Int? {
        dateParts.first?.first
    }
}
