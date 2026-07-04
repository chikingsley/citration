import Foundation

public enum CitationExportFormat: String, Codable, CaseIterable, Sendable {
    case cslJSON
    case bibTeX

    public var displayName: String {
        switch self {
        case .cslJSON:
            return "CSL JSON"
        case .bibTeX:
            return "BibTeX"
        }
    }
}

public struct CitationExportResult: Hashable, Codable, Sendable {
    public var format: CitationExportFormat
    public var text: String

    public init(format: CitationExportFormat, text: String) {
        self.format = format
        self.text = text
    }
}

public struct CitationExporter: Sendable {
    public init() {}

    public func export(items: [BCItem], format: CitationExportFormat) throws -> CitationExportResult {
        switch format {
        case .cslJSON:
            return CitationExportResult(format: format, text: try cslJSON(for: items))
        case .bibTeX:
            return CitationExportResult(format: format, text: bibTeX(for: items))
        }
    }

    public func cslJSON(for items: [BCItem]) throws -> String {
        let cslItems = items.map { CSLItem(item: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(cslItems)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CitationEngineError.invalidInput("CSL JSON must be valid UTF-8")
        }
        return json
    }

    public func bibTeX(for items: [BCItem]) -> String {
        var usedKeys = Set<String>()
        return items
            .map { item in
                bibTeXEntry(for: item, citationKey: citationKey(for: item, usedKeys: &usedKeys))
            }
            .joined(separator: "\n\n")
    }

    private func bibTeXEntry(for item: BCItem, citationKey: String) -> String {
        var fields = [(String, String)]()
        fields.append(("title", item.title.bcCollapsedWhitespace()))

        let authors = item.creators.map(\.bibTeXName).filter { !$0.isEmpty }
        if !authors.isEmpty {
            fields.append(("author", authors.joined(separator: " and ")))
        }

        if let year = item.publicationYear {
            fields.append(("year", String(year)))
        }

        for identifier in item.identifiers {
            switch identifier.type {
            case .doi:
                fields.append(("doi", identifier.value))
            case .isbn:
                fields.append(("isbn", identifier.value))
            case .pmid:
                fields.append(("pmid", identifier.value))
            case .arxiv:
                fields.append(("eprint", identifier.value))
                fields.append(("archivePrefix", "arXiv"))
            case .url:
                fields.append(("url", identifier.value))
            }
        }

        let renderedFields = fields.map { name, value in
            "  \(name) = {\(Self.escapeBibTeX(value))}"
        }

        return """
        @\(item.itemType.bibTeXType){\(citationKey),
        \(renderedFields.joined(separator: ",\n"))
        }
        """
    }

    private func citationKey(for item: BCItem, usedKeys: inout Set<String>) -> String {
        let creator = item.creators.first?.citationKeyComponent
        let year = item.publicationYear.map(String.init)
        let title = item.title.bcCitationKeyComponent
        let rawKey = [creator, year, title].compactMap { $0 }.joined()
        let baseKey = rawKey.isEmpty ? String(item.id.uuidString.prefix(8)).lowercased() : rawKey

        var key = baseKey
        var suffix = 2
        while usedKeys.contains(key) {
            key = "\(baseKey)\(suffix)"
            suffix += 1
        }
        usedKeys.insert(key)
        return key
    }

    private static func escapeBibTeX(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\textbackslash{}")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
    }
}

private struct CSLItem: Codable {
    var id: String
    var type: String
    var title: String
    var author: [CSLCreator]?
    var issued: CSLDate?
    var doi: String?
    var isbn: String?
    var pmid: String?
    var url: String?
    var archive: String?
    var archiveLocation: String?

    init(item: BCItem) {
        id = item.id.uuidString
        type = item.itemType.cslType
        title = item.title.bcCollapsedWhitespace()
        let creators = item.creators.map(CSLCreator.init)
        author = creators.isEmpty ? nil : creators
        issued = item.publicationYear.map { CSLDate(year: $0) }

        for identifier in item.identifiers {
            switch identifier.type {
            case .doi:
                doi = identifier.value
            case .isbn:
                isbn = identifier.value
            case .pmid:
                pmid = identifier.value
            case .url:
                url = identifier.value
            case .arxiv:
                archive = "arXiv"
                archiveLocation = identifier.value
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case author
        case issued
        case doi = "DOI"
        case isbn = "ISBN"
        case pmid = "PMID"
        case url = "URL"
        case archive
        case archiveLocation = "archive_location"
    }
}

private struct CSLCreator: Codable {
    var given: String?
    var family: String?
    var literal: String?

    init(creator: Creator) {
        if let literalName = creator.literalName?.bcTrimmedNonEmpty {
            literal = literalName
        } else {
            given = creator.givenName?.bcTrimmedNonEmpty
            family = creator.familyName?.bcTrimmedNonEmpty
        }
    }
}

private struct CSLDate: Codable {
    var dateParts: [[Int]]

    init(year: Int) {
        dateParts = [[year]]
    }

    private enum CodingKeys: String, CodingKey {
        case dateParts = "date-parts"
    }
}

private extension ItemType {
    var cslType: String {
        switch self {
        case .article:
            return "article-journal"
        case .book:
            return "book"
        case .preprint:
            return "article"
        case .thesis:
            return "thesis"
        case .dataset:
            return "dataset"
        case .webpage:
            return "webpage"
        case .unknown:
            return "document"
        }
    }

    var bibTeXType: String {
        switch self {
        case .article, .preprint:
            return "article"
        case .book:
            return "book"
        case .thesis:
            return "phdthesis"
        case .dataset, .webpage, .unknown:
            return "misc"
        }
    }
}

private extension Creator {
    var bibTeXName: String {
        if let literalName = literalName?.bcTrimmedNonEmpty {
            return literalName
        }

        switch (familyName?.bcTrimmedNonEmpty, givenName?.bcTrimmedNonEmpty) {
        case let (family?, given?):
            return "\(family), \(given)"
        case let (family?, nil):
            return family
        case let (nil, given?):
            return given
        case (nil, nil):
            return ""
        }
    }

    var citationKeyComponent: String? {
        (familyName ?? literalName)?.bcCitationKeyComponent
    }
}

private extension String {
    func bcCollapsedWhitespace() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var bcTrimmedNonEmpty: String? {
        let normalized = bcCollapsedWhitespace()
        return normalized.isEmpty ? nil : normalized
    }

    var bcCitationKeyComponent: String? {
        let normalized = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .prefix(3)
            .joined()
            .lowercased()

        return normalized.isEmpty ? nil : normalized
    }
}
