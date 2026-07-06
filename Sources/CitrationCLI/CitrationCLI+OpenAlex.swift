import CitrationCore
import Foundation

extension CitrationCLI {
    func openAlexKey(arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            printOpenAlexKeyHelp()
            return
        }

        let store = FileAPIKeyStore()
        switch subcommand {
        case "status":
            if await store.loadAPIKey() != nil {
                print("OpenAlex key: configured")
            } else if openAlexAPIKeyFromEnvironmentOrDotEnv() != nil {
                print("OpenAlex key: available from environment or .env")
            } else {
                print("OpenAlex key: not configured")
            }

        case "import-env":
            guard let apiKey = openAlexAPIKeyFromEnvironmentOrDotEnv() else {
                throw cliError("OPENALEX_API_KEY was not found in the process environment or root .env")
            }
            await store.saveAPIKey(apiKey)
            print("Imported OpenAlex key")

        case "clear":
            await store.saveAPIKey(nil)
            print("Cleared OpenAlex key")

        case "help",
             "--help",
             "-h":
            printOpenAlexKeyHelp()

        default:
            throw cliError("Unknown openalex-key command: \(subcommand)")
        }
    }

    func openAlexSmoke(arguments: [String]) async throws {
        guard let doi = arguments.first?.trimmedNonEmpty else {
            throw cliError("Usage: swift run citration openalex-smoke <doi>")
        }

        let apiKey = try await resolvedOpenAlexAPIKey()
        let client = OpenAlexSmokeClient(apiKey: apiKey)
        let report = try await client.report(for: doi)

        print("OpenAlex smoke: \(doi)")
        print("Source: \(report.sourceTitle) [\(report.sourceWorkID)]")
        for section in report.sections {
            print("\(section.label): \(section.works.count)")
            for work in section.works.prefix(3) {
                print("  - \(work.title) (\(work.yearText)) [\(work.workID)]")
            }
        }
    }

    private func printOpenAlexKeyHelp() {
        print("""
        OpenAlex key commands

        Usage:
          swift run citration openalex-key status
          swift run citration openalex-key import-env
          swift run citration openalex-key clear
        """)
    }

    private func resolvedOpenAlexAPIKey() async throws -> String {
        let store = FileAPIKeyStore()
        if let apiKey = await store.loadAPIKey() {
            return apiKey
        }
        if let apiKey = openAlexAPIKeyFromEnvironmentOrDotEnv() {
            return apiKey
        }
        throw cliError("OpenAlex key is not configured; run openalex-key import-env after adding OPENALEX_API_KEY to .env")
    }

    private func openAlexAPIKeyFromEnvironmentOrDotEnv() -> String? {
        if let apiKey = ProcessInfo.processInfo.environment["OPENALEX_API_KEY"]?.trimmedNonEmpty {
            return apiKey
        }
        return dotenvValue(named: "OPENALEX_API_KEY")
    }

    private func dotenvValue(named key: String) -> String? {
        let dotenvURL = repoRoot.appendingPathComponent(".env")
        guard let contents = try? String(contentsOf: dotenvURL, encoding: .utf8) else {
            return nil
        }

        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { value(for: String($0), key: key) }
            .first
    }

    private func value(for line: String, key: String) -> String? {
        var line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("export ") {
            line.removeFirst("export ".count)
        }
        guard
            !line.hasPrefix("#"),
            let separator = line.firstIndex(of: "=")
        else {
            return nil
        }

        let lineKey = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard lineKey == key else {
            return nil
        }

        var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        if
            value.count >= 2,
            let first = value.first,
            let last = value.last,
            first == last,
            first == "\"" || first == "'"
        {
            value.removeFirst()
            value.removeLast()
        }
        return value.trimmedNonEmpty
    }

    private func cliError(_ message: String) -> NSError {
        NSError(
            domain: "CitrationCLI",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

// MARK: - OpenAlexSmokeClient

private struct OpenAlexSmokeClient {
    // MARK: Internal

    let apiKey: String

    func report(for doi: String) async throws -> OpenAlexSmokeReport {
        let sourceWorks = try await works(
            filter: "doi:https://doi.org/\(doi)",
            limit: 1
        )
        guard
            let source = sourceWorks.first,
            let sourceWorkID = source.workID
        else {
            throw NSError(
                domain: "CitrationCLI",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "OpenAlex did not resolve the DOI"]
            )
        }

        let sections = try await filters(for: source, sourceWorkID: sourceWorkID).asyncMap { filter in
            let works = try await works(filter: filter.value, limit: 5)
            return OpenAlexSmokeSection(
                label: filter.label,
                works: works
                    .filter { $0.workID != sourceWorkID }
                    .compactMap(OpenAlexSmokeWorkSummary.init)
            )
        }

        return OpenAlexSmokeReport(
            sourceWorkID: sourceWorkID,
            sourceTitle: source.displayName ?? "Untitled",
            sections: sections
        )
    }

    // MARK: Private

    private func filters(
        for source: OpenAlexSmokeWork,
        sourceWorkID: String
    ) -> [OpenAlexSmokeFilter] {
        var filters = [OpenAlexSmokeFilter(label: "related_to", value: "related_to:\(sourceWorkID)")]

        if let authorID = source.firstAuthorID {
            filters.append(OpenAlexSmokeFilter(label: "same author", value: "author.id:\(authorID)"))
        }
        if let institutionID = source.firstInstitutionID {
            filters.append(OpenAlexSmokeFilter(label: "same institution", value: "institutions.id:\(institutionID)"))
        }
        if let topicID = source.primaryTopicID {
            filters.append(OpenAlexSmokeFilter(label: "same topic", value: "primary_topic.id:\(topicID)"))
        }

        filters.append(OpenAlexSmokeFilter(label: "cites source", value: "cites:\(sourceWorkID)"))
        filters.append(OpenAlexSmokeFilter(label: "source references", value: "cited_by:\(sourceWorkID)"))
        return filters
    }

    private func works(filter: String, limit: Int) async throws -> [OpenAlexSmokeWork] {
        guard let url = url(filter: filter, limit: limit) else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CitrationCLI/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200 ..< 300).contains(httpResponse.statusCode)
        else {
            return []
        }

        return (try? JSONDecoder().decode(OpenAlexSmokeEnvelope.self, from: data).results) ?? []
    }

    private func url(filter: String, limit: Int) -> URL? {
        guard let endpointURL = URL(string: "https://api.openalex.org/works") else {
            return nil
        }

        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "per-page", value: String(max(1, min(limit, 25)))),
            URLQueryItem(name: "select", value: OpenAlexSmokeWork.selectFields),
            URLQueryItem(name: "sort", value: "cited_by_count:desc"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        return components?.url
    }
}

// MARK: - OpenAlexSmokeReport

private struct OpenAlexSmokeReport {
    let sourceWorkID: String
    let sourceTitle: String
    let sections: [OpenAlexSmokeSection]
}

// MARK: - OpenAlexSmokeSection

private struct OpenAlexSmokeSection {
    let label: String
    let works: [OpenAlexSmokeWorkSummary]
}

// MARK: - OpenAlexSmokeFilter

private struct OpenAlexSmokeFilter {
    let label: String
    let value: String
}

// MARK: - OpenAlexSmokeEnvelope

private struct OpenAlexSmokeEnvelope: Decodable {
    let results: [OpenAlexSmokeWork]
}

// MARK: - OpenAlexSmokeWork

private struct OpenAlexSmokeWork: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case publicationYear = "publication_year"
        case authorships
        case primaryTopic = "primary_topic"
    }

    static let selectFields = "id,display_name,doi,publication_year,type,authorships,primary_topic,topics"

    let id: String?
    let displayName: String?
    let publicationYear: Int?
    let authorships: [OpenAlexSmokeAuthorship]?
    let primaryTopic: OpenAlexSmokeTopic?

    var workID: String? {
        shortOpenAlexID(from: id)
    }

    var firstAuthorID: String? {
        authorships?.compactMap(\.author?.shortID).first
    }

    var firstInstitutionID: String? {
        authorships?.flatMap { $0.institutions ?? [] }.compactMap(\.shortID).first
    }

    var primaryTopicID: String? {
        primaryTopic?.shortID
    }
}

// MARK: - OpenAlexSmokeAuthorship

private struct OpenAlexSmokeAuthorship: Decodable {
    let author: OpenAlexSmokeAuthor?
    let institutions: [OpenAlexSmokeInstitution]?
}

// MARK: - OpenAlexSmokeAuthor

private struct OpenAlexSmokeAuthor: Decodable {
    let id: String?

    var shortID: String? {
        shortOpenAlexID(from: id)
    }
}

// MARK: - OpenAlexSmokeInstitution

private struct OpenAlexSmokeInstitution: Decodable {
    let id: String?

    var shortID: String? {
        shortOpenAlexID(from: id)
    }
}

// MARK: - OpenAlexSmokeTopic

private struct OpenAlexSmokeTopic: Decodable {
    let id: String?

    var shortID: String? {
        shortOpenAlexID(from: id)
    }
}

// MARK: - OpenAlexSmokeWorkSummary

private struct OpenAlexSmokeWorkSummary {
    // MARK: Lifecycle

    init?(_ work: OpenAlexSmokeWork) {
        guard let workID = work.workID else {
            return nil
        }
        self.workID = workID
        title = work.displayName ?? "Untitled"
        yearText = work.publicationYear.map(String.init) ?? "n.d."
    }

    // MARK: Internal

    let workID: String
    let title: String
    let yearText: String
}

private func shortOpenAlexID(from id: String?) -> String? {
    guard let id = id?.trimmedNonEmpty else {
        return nil
    }
    return id.split(separator: "/").last.map(String.init)
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values = [T]()
        for element in self {
            let value = try await transform(element)
            values.append(value)
        }
        return values
    }
}
