import CitrationCore
import Foundation

/// Turns OCR markdown into the same candidate shape the text-layer
/// extractor produces: ordered identifiers plus title hints taken
/// from the first page.
enum OCRTextParsing {
    // MARK: Internal

    static func candidates(fromMarkdown markdown: String) -> PDFMetadataCandidates {
        PDFMetadataCandidates(
            identifiers: identifiers(in: markdown),
            titleHints: titleHints(fromMarkdown: markdown)
        )
    }

    static func identifiers(in text: String) -> [Identifier] {
        var identifiers = [Identifier]()

        for arXiv in ArXivParsing.candidates(in: text) {
            identifiers.append(Identifier(type: .arxiv, value: arXiv))
        }

        for doi in DOIParsing.candidates(in: text) {
            identifiers.append(Identifier(type: .doi, value: doi))
        }

        for isbn in ISBNParsing.candidates(in: text) {
            identifiers.append(Identifier(type: .isbn, value: isbn))
        }

        return dedupeIdentifiersPreservingOrder(identifiers)
    }

    /// Title guesses from the first page: the leading lines joined into
    /// one candidate (scanned title pages often break the title across
    /// lines), followed by each heading line individually.
    static func titleHints(fromMarkdown markdown: String) -> [String] {
        let firstPage = markdown
            .components(separatedBy: "\n\n---\n\n")
            .first ?? markdown

        let lines = firstPage
            .split(separator: "\n")
            .map { line in
                line.replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("<!--") && letterCount(in: line) >= 4
            }

        var hints = [String]()
        let joined = lines.prefix(4).joined(separator: " ").bcCollapsedWhitespace()
        if !joined.isEmpty {
            hints.append(joined)
        }

        for line in lines.prefix(4) where !hints.contains(line) {
            hints.append(line)
        }

        return hints
    }

    // MARK: Private

    private static func letterCount(in line: String) -> Int {
        line.unicodeScalars.count { CharacterSet.letters.contains($0) }
    }
}
