import CitrationCore
import Foundation

enum DOIParsing {
    // MARK: Internal

    static func candidates(in text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = candidateRegex.matches(in: text, range: range)

        var seen = Set<String>()
        var ordered = [String]()

        for match in matches {
            let raw = nsText.substring(with: match.range)
            guard let normalized = normalizeCandidate(raw) else {
                continue
            }
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }

        return ordered
    }

    static func normalizeCandidate(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return nil
        }

        if value.lowercased().hasPrefix("doi:") {
            value = String(value.dropFirst(4))
        }

        while let scalar = value.unicodeScalars.last, trailingNoiseCharacters.contains(scalar) {
            value.removeLast()
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        let nsValue = value as NSString
        let range = NSRange(location: 0, length: nsValue.length)
        guard validationRegex.firstMatch(in: value, range: range) != nil else {
            return nil
        }

        return value.lowercased()
    }

    // MARK: Private

    private static let candidateRegex = makeStaticRegex(
        pattern: #"(?i)\b10\.\d{4,9}/[^\s"<>]+"#,
        name: "DOI candidate"
    )

    private static let validationRegex = makeStaticRegex(
        pattern: #"(?i)^10\.\d{4,9}/\S+$"#,
        name: "DOI validation"
    )

    private static let trailingNoiseCharacters: CharacterSet = .init(charactersIn: ".,;:!?\"'`»”’]}>)")
}
