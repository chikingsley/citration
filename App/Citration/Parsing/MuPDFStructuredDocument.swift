import Foundation

// MARK: - MuPDFStructuredDocument

struct MuPDFStructuredDocument: Decodable {
    let pages: [MuPDFStructuredPage]

    var allText: String {
        pages
            .flatMap(\.blocks)
            .flatMap(\.lines)
            .compactMap(\.text)
            .map { $0.bcCollapsedWhitespace() }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

// MARK: - MuPDFStructuredPage

struct MuPDFStructuredPage: Decodable {
    let blocks: [MuPDFStructuredBlock]
}

// MARK: - MuPDFStructuredBlock

struct MuPDFStructuredBlock: Decodable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        lines = try container.decodeIfPresent([MuPDFStructuredLine].self, forKey: .lines) ?? []
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case type
        case lines
    }

    let type: String?
    let lines: [MuPDFStructuredLine]
}

// MARK: - MuPDFStructuredLine

struct MuPDFStructuredLine: Decodable {
    let text: String?
    let x: Double?
    let y: Double?
    let font: MuPDFStructuredFont?
}

// MARK: - MuPDFStructuredFont

struct MuPDFStructuredFont: Decodable {
    let size: Double?
}

func titleHints(from document: MuPDFStructuredDocument) -> [String] {
    guard let firstPage = document.pages.first else {
        return []
    }

    var scored = [(title: String, score: Double)]()

    for block in firstPage.blocks where block.type == nil || block.type == "text" {
        for line in block.lines {
            guard let rawText = line.text else {
                continue
            }
            let text = rawText.bcCollapsedWhitespace()
            guard isPotentialTitleLine(text) else {
                continue
            }

            let fontSize = line.font?.size ?? 12
            let y = line.y ?? 9999
            let score = fontSize - (y / 140.0)
            scored.append((title: text, score: score))
        }
    }

    let sorted = scored
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.title.count > rhs.title.count
            }
            return lhs.score > rhs.score
        }

    var seen = Set<String>()
    var unique = [String]()
    for candidate in sorted.map(\.title) {
        let key = candidate.lowercased()
        if seen.insert(key).inserted {
            unique.append(candidate)
        }
        if unique.count == 3 {
            break
        }
    }

    return unique
}

private func isPotentialTitleLine(_ text: String) -> Bool {
    let trimmed = text.bcCollapsedWhitespace()
    guard trimmed.count >= 16, trimmed.count <= 240 else {
        return false
    }
    guard trimmed.contains(" ") else {
        return false
    }

    let lower = trimmed.lowercased()
    if
        lower.hasPrefix("doi:")
        || lower.contains("arxiv:")
        || lower.hasPrefix("http://")
        || lower.hasPrefix("https://")
    {
        return false
    }

    if
        DOIParsing.normalizeCandidate(trimmed) != nil
        || ArXivParsing.normalizeCandidate(trimmed) != nil
        || ISBNParsing.normalizeCandidate(trimmed) != nil
    {
        return false
    }

    let letters = trimmed.unicodeScalars.count(where: { CharacterSet.letters.contains($0) })
    let digits = trimmed.unicodeScalars.count(where: { CharacterSet.decimalDigits.contains($0) })
    guard letters >= 10 else {
        return false
    }
    if digits > letters {
        return false
    }

    return true
}
