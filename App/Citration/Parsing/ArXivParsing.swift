import CitrationCore
import Foundation

enum ArXivParsing {
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
            guard match.numberOfRanges > 1 else {
                continue
            }
            let raw = nsText.substring(with: match.range(at: 1))
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
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("arxiv:") {
            value = String(value.dropFirst(6))
        }

        value = value.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
        let nsValue = value as NSString
        let range = NSRange(location: 0, length: nsValue.length)

        if modernValidationRegex.firstMatch(in: value, range: range) != nil {
            return value
        }

        if classicValidationRegex.firstMatch(in: value, range: range) != nil {
            return value
        }

        return nil
    }

    // MARK: Private

    private static let candidateRegex = makeStaticRegex(
        pattern: #"(?i)\b(?:arxiv\s*:\s*)?((?:[-a-z.]+/\d{7}(?:v\d+)?)|(?:\d{4}\.\d{4,5}(?:v\d+)?))\b"#,
        name: "arXiv candidate"
    )

    private static let modernValidationRegex = makeStaticRegex(
        pattern: #"(?i)^\d{4}\.\d{4,5}$"#,
        name: "arXiv modern validation"
    )

    private static let classicValidationRegex = makeStaticRegex(
        pattern: #"(?i)^[-a-z.]+/\d{7}$"#,
        name: "arXiv classic validation"
    )
}
