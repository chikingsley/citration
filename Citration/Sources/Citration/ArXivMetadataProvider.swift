import CitrationCore
import Foundation

// MARK: - ArXivMetadataProvider

struct ArXivMetadataProvider: MetadataProvider {
    // MARK: Lifecycle

    init(
        session: URLSession = .shared,
        endpointBaseURL: URL = Self.defaultEndpointBaseURL
    ) {
        self.session = session
        self.endpointBaseURL = endpointBaseURL
    }

    // MARK: Internal

    let name: String = "arxiv"

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
            URLQueryItem(name: "max_results", value: "1"),
        ]

        guard let url = components?.url else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        request.setValue("Citration/1.0 (mailto:support@citration.app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200 ..< 300).contains(httpResponse.statusCode),
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
                    "publicationYear": "arxiv.entry.published",
                ]
            ),
            rawPayload: data
        )

        return [record]
    }

    // MARK: Private

    private static let defaultEndpointBaseURL = requireEndpointURL(
        "https://export.arxiv.org/api/query",
        providerName: "arXiv"
    )

    private let session: URLSession
    private let endpointBaseURL: URL

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

// MARK: - ArXivEntry

private struct ArXivEntry {
    let title: String?
    let authors: [String]
    let publishedYear: Int?
    let doi: String?
}

// MARK: - ArXivAtomParser

private enum ArXivAtomParser {
    // MARK: Internal

    static func parseFirstEntry(from data: Data) -> ArXivEntry? {
        guard let xml = String(data: data, encoding: .utf8) else {
            return nil
        }

        guard
            let entryXML = firstMatch(
                pattern: #"<entry\b[^>]*>(.*?)</entry>"#,
                in: xml,
                captureGroup: 1
            )
        else {
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

        let publishedYear: Int? = if let publishedRaw, publishedRaw.count >= 4 {
            Int(publishedRaw.prefix(4))
        } else {
            nil
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

    // MARK: Private

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
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            )
        else {
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
            ("&#39;", "'"),
        ]
        for (entity, replacement) in replacements {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
    }
}
