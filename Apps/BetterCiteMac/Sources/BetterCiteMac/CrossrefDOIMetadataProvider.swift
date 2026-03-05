import Foundation
import BCMetadataProviders
import BCCommon

struct CrossrefDOIMetadataProvider: MetadataProvider {
    let name: String = "crossref-doi"

    private static let defaultEndpointBaseURL = requireEndpointURL(
        "https://api.crossref.org/works/",
        providerName: "Crossref DOI"
    )

    private let session: URLSession
    private let endpointBaseURL: URL

    init(
        session: URLSession = .shared,
        endpointBaseURL: URL = Self.defaultEndpointBaseURL
    ) {
        self.session = session
        self.endpointBaseURL = endpointBaseURL
    }

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
        request.setValue("BetterCite/1.0 (mailto:support@bettercite.app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
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
            URLQueryItem(name: "rows", value: "1")
        ]

        guard let url = components?.url else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BetterCite/1.0 (mailto:support@bettercite.app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            let search = try? JSONDecoder().decode(CrossrefSearchEnvelope.self, from: data),
            let message = search.message.items.first
        else {
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
                    "publicationYear": "crossref.message.issued|published-*"
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
        case "journal-article", "proceedings-article", "reference-entry":
            return .article
        case "book", "book-chapter", "book-part":
            return .book
        case "posted-content":
            return .preprint
        case "dissertation":
            return .thesis
        case "dataset":
            return .dataset
        case "report", "standard":
            return .webpage
        default:
            return .unknown
        }
    }
}

struct ArXivMetadataProvider: MetadataProvider {
    let name: String = "arxiv"

    private static let defaultEndpointBaseURL = requireEndpointURL(
        "https://export.arxiv.org/api/query",
        providerName: "arXiv"
    )

    private let session: URLSession
    private let endpointBaseURL: URL

    init(
        session: URLSession = .shared,
        endpointBaseURL: URL = Self.defaultEndpointBaseURL
    ) {
        self.session = session
        self.endpointBaseURL = endpointBaseURL
    }

    func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord] {
        guard
            let rawArXiv = request.identifiers.first(where: { $0.type == .arxiv })?.value,
            let arXiv = ArXivParsing.normalizeCandidate(rawArXiv)
        else {
            return []
        }

        var components = URLComponents(url: endpointBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id_list", value: arXiv),
            URLQueryItem(name: "max_results", value: "1")
        ]

        guard let url = components?.url else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        request.setValue("BetterCite/1.0 (mailto:support@bettercite.app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            let entry = ArXivAtomParser.parseFirstEntry(from: data)
        else {
            return []
        }

        let title = entry.title?.bcTrimmedNonEmpty ?? "arXiv \(arXiv)"
        let creators = entry.authors.compactMap(makeCreator(from:))
        let publicationYear = entry.publishedYear

        var identifiers = [Identifier(type: .arxiv, value: arXiv)]
        if
            let doi = entry.doi,
            let normalizedDOI = DOIParsing.normalizeCandidate(doi)
        {
            identifiers.append(Identifier(type: .doi, value: normalizedDOI))
        }

        let record = CanonicalMetadataRecord(
            title: title,
            creators: creators,
            publicationYear: publicationYear,
            itemType: .preprint,
            identifiers: identifiers,
            sourceURL: URL(string: "https://arxiv.org/abs/\(arXiv)"),
            confidence: 0.98,
            provenance: MetadataProvenance(
                providerName: name,
                sourceRecordID: arXiv,
                fieldSources: [
                    "title": "arxiv.entry.title",
                    "creators": "arxiv.entry.author.name",
                    "publicationYear": "arxiv.entry.published"
                ]
            ),
            rawPayload: data
        )

        return [record]
    }

    private func makeCreator(from displayName: String) -> Creator? {
        let cleaned = displayName.bcTrimmedNonEmpty
        guard let cleaned else {
            return nil
        }

        let parts = cleaned.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            return Creator(
                givenName: parts.dropLast().joined(separator: " "),
                familyName: parts.last
            )
        }

        return Creator(literalName: cleaned)
    }
}

struct OpenLibraryISBNMetadataProvider: MetadataProvider {
    let name: String = "openlibrary-isbn"

    private static let defaultEndpointBaseURL = requireEndpointURL(
        "https://openlibrary.org/isbn/",
        providerName: "OpenLibrary ISBN"
    )

    private let session: URLSession
    private let endpointBaseURL: URL

    init(
        session: URLSession = .shared,
        endpointBaseURL: URL = Self.defaultEndpointBaseURL
    ) {
        self.session = session
        self.endpointBaseURL = endpointBaseURL
    }

    func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord] {
        guard
            let rawISBN = request.identifiers.first(where: { $0.type == .isbn })?.value,
            let isbn = ISBNParsing.normalizeCandidate(rawISBN),
            let url = URL(string: "\(isbn).json", relativeTo: endpointBaseURL)
        else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BetterCite/1.0 (mailto:support@bettercite.app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            let payload = try? JSONDecoder().decode(OpenLibraryISBNResponse.self, from: data)
        else {
            return []
        }

        let title = payload.title.bcTrimmedNonEmpty ?? "ISBN \(isbn)"
        let publicationYear = payload.publishDate.flatMap(firstYear(in:))

        let record = CanonicalMetadataRecord(
            title: title,
            publicationYear: publicationYear,
            itemType: .book,
            identifiers: [Identifier(type: .isbn, value: isbn)],
            confidence: 0.9,
            provenance: MetadataProvenance(
                providerName: name,
                sourceRecordID: isbn,
                fieldSources: [
                    "title": "openlibrary.title",
                    "publicationYear": "openlibrary.publish_date"
                ]
            ),
            rawPayload: data
        )

        return [record]
    }

    private func firstYear(in raw: String) -> Int? {
        let pattern = #"(19|20)\d{2}"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: raw,
                range: NSRange(location: 0, length: (raw as NSString).length)
            )
        else {
            return nil
        }

        let yearText = (raw as NSString).substring(with: match.range)
        return Int(yearText)
    }
}

private struct CrossrefEnvelope: Decodable {
    let message: CrossrefMessage
}

private struct CrossrefSearchEnvelope: Decodable {
    let message: CrossrefSearchMessage
}

private struct CrossrefSearchMessage: Decodable {
    let items: [CrossrefMessage]
}

private struct CrossrefMessage: Decodable {
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

    var publicationYear: Int? {
        publishedPrint?.firstYear
            ?? publishedOnline?.firstYear
            ?? issued?.firstYear
            ?? created?.firstYear
    }
}

private struct CrossrefAuthor: Decodable {
    let given: String?
    let family: String?
    let name: String?
}

private struct CrossrefDateParts: Decodable {
    let dateParts: [[Int]]

    enum CodingKeys: String, CodingKey {
        case dateParts = "date-parts"
    }

    var firstYear: Int? {
        dateParts.first?.first
    }
}

private struct OpenLibraryISBNResponse: Decodable {
    let title: String
    let publishDate: String?

    enum CodingKeys: String, CodingKey {
        case title
        case publishDate = "publish_date"
    }
}

private struct ArXivEntry {
    let title: String?
    let authors: [String]
    let publishedYear: Int?
    let doi: String?
}

private enum ArXivAtomParser {
    static func parseFirstEntry(from data: Data) -> ArXivEntry? {
        guard let xml = String(data: data, encoding: .utf8) else {
            return nil
        }

        guard let entryXML = firstMatch(
            pattern: #"<entry\b[^>]*>(.*?)</entry>"#,
            in: xml,
            captureGroup: 1
        ) else {
            return nil
        }

        let title = firstMatch(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            in: entryXML,
            captureGroup: 1
        )?.decodedXMLEntities().bcCollapsedWhitespace()

        let publishedRaw = firstMatch(
            pattern: #"<published\b[^>]*>(.*?)</published>"#,
            in: entryXML,
            captureGroup: 1
        )?.decodedXMLEntities().bcCollapsedWhitespace()

        let publishedYear: Int?
        if let publishedRaw, publishedRaw.count >= 4 {
            publishedYear = Int(publishedRaw.prefix(4))
        }
        else {
            publishedYear = nil
        }

        let doi =
            firstMatch(
                pattern: #"<arxiv:doi\b[^>]*>(.*?)</arxiv:doi>"#,
                in: entryXML,
                captureGroup: 1
            )?.decodedXMLEntities().bcCollapsedWhitespace()
            ?? firstMatch(
                pattern: #"<doi\b[^>]*>(.*?)</doi>"#,
                in: entryXML,
                captureGroup: 1
            )?.decodedXMLEntities().bcCollapsedWhitespace()

        let authorNames = allMatches(
            pattern: #"<author\b[^>]*>\s*<name\b[^>]*>(.*?)</name>\s*</author>"#,
            in: entryXML,
            captureGroup: 1
        ).map { $0.decodedXMLEntities().bcCollapsedWhitespace() }
            .filter { !$0.isEmpty }

        return ArXivEntry(
            title: title,
            authors: authorNames,
            publishedYear: publishedYear,
            doi: doi
        )
    }

    private static func firstMatch(
        pattern: String,
        in text: String,
        captureGroup: Int
    ) -> String? {
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            ),
            let match = regex.firstMatch(
                in: text,
                range: NSRange(location: 0, length: (text as NSString).length)
            ),
            match.numberOfRanges > captureGroup
        else {
            return nil
        }

        return (text as NSString).substring(with: match.range(at: captureGroup))
    }

    private static func allMatches(
        pattern: String,
        in text: String,
        captureGroup: Int
    ) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return []
        }

        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        )

        return matches.compactMap { match in
            guard match.numberOfRanges > captureGroup else {
                return nil
            }
            return (text as NSString).substring(with: match.range(at: captureGroup))
        }
    }
}

private extension String {
    func decodedXMLEntities() -> String {
        var value = self
        let replacements = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'")
        ]
        for (entity, replacement) in replacements {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
    }
}

private func requireEndpointURL(_ rawURL: String, providerName: String) -> URL {
    guard let url = URL(string: rawURL) else {
        fatalError("Invalid default endpoint URL for \(providerName): \(rawURL)")
    }
    return url
}
