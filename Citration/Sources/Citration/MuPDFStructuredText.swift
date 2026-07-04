import Foundation

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

struct MuPDFStructuredPage: Decodable {
    let blocks: [MuPDFStructuredBlock]
}

struct MuPDFStructuredBlock: Decodable {
    let type: String?
    let lines: [MuPDFStructuredLine]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.lines = try container.decodeIfPresent([MuPDFStructuredLine].self, forKey: .lines) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case type
        case lines
    }
}

struct MuPDFStructuredLine: Decodable {
    let text: String?
    let x: Double?
    let y: Double?
    let font: MuPDFStructuredFont?
}

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
    if lower.hasPrefix("doi:")
        || lower.contains("arxiv:")
        || lower.hasPrefix("http://")
        || lower.hasPrefix("https://") {
        return false
    }

    if DOIParsing.normalizeCandidate(trimmed) != nil
        || ArXivParsing.normalizeCandidate(trimmed) != nil
        || ISBNParsing.normalizeCandidate(trimmed) != nil {
        return false
    }

    let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
    guard letters >= 10 else {
        return false
    }
    if digits > letters {
        return false
    }

    return true
}
