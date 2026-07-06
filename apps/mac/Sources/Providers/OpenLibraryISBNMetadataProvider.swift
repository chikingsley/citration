import CitrationCore
import Foundation

// MARK: - OpenLibraryISBNMetadataProvider

struct OpenLibraryISBNMetadataProvider: MetadataProvider {
    // MARK: Lifecycle

    init(
        session: URLSession = .shared,
        endpointBaseURL: URL = Self.defaultEndpointBaseURL
    ) {
        self.session = session
        self.endpointBaseURL = endpointBaseURL
    }

    // MARK: Internal

    let name: String = "openlibrary-isbn"

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
        request.setValue("Citration/1.0 (mailto:support@citration.app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200 ..< 300).contains(httpResponse.statusCode),
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
                    "publicationYear": "openlibrary.publish_date",
                ]
            ),
            rawPayload: data
        )

        return [record]
    }

    // MARK: Private

    private static let defaultEndpointBaseURL = requireEndpointURL(
        "https://openlibrary.org/isbn/",
        providerName: "OpenLibrary ISBN"
    )

    private let session: URLSession
    private let endpointBaseURL: URL

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

// MARK: - OpenLibraryISBNResponse

private struct OpenLibraryISBNResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case title
        case publishDate = "publish_date"
    }

    let title: String
    let publishDate: String?
}
