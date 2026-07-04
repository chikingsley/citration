import Foundation
import CitrationCore

enum DOIParsing {
    private static let candidateRegex = makeStaticRegex(
        pattern: #"(?i)\b10\.\d{4,9}/[^\s"<>]+"#,
        name: "DOI candidate"
    )

    private static let validationRegex = makeStaticRegex(
        pattern: #"(?i)^10\.\d{4,9}/\S+$"#,
        name: "DOI validation"
    )

    private static let trailingNoiseCharacters = CharacterSet(charactersIn: ".,;:!?\"'`»”’]}>)")

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
}

enum ArXivParsing {
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
}

enum ISBNParsing {
    private static let candidateRegex = makeStaticRegex(
        pattern: #"(?i)\b(?:isbn(?:-1[03])?\s*:?)?\s*((?:97[89][\d\-\s]{10,20})|(?:[\dX][\d\-\s]{8,20}))\b"#,
        name: "ISBN candidate"
    )

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
        let filteredScalars = raw.uppercased().unicodeScalars.filter { scalar in
            CharacterSet.decimalDigits.contains(scalar) || scalar == "X"
        }
        let value = String(String.UnicodeScalarView(filteredScalars))

        if value.count == 13, isValidISBN13(value) {
            return value
        }
        if value.count == 10, isValidISBN10(value) {
            return value
        }
        return nil
    }

    private static func isValidISBN10(_ value: String) -> Bool {
        guard value.count == 10 else {
            return false
        }

        let chars = Array(value)
        var total = 0

        for index in 0..<9 {
            guard let digit = chars[index].wholeNumberValue else {
                return false
            }
            total += (10 - index) * digit
        }

        let checksum: Int
        if chars[9] == "X" {
            checksum = 10
        }
        else if let digit = chars[9].wholeNumberValue {
            checksum = digit
        }
        else {
            return false
        }

        total += checksum
        return total % 11 == 0
    }

    private static func isValidISBN13(_ value: String) -> Bool {
        guard value.count == 13 else {
            return false
        }

        let chars = Array(value)
        var total = 0

        for index in 0..<12 {
            guard let digit = chars[index].wholeNumberValue else {
                return false
            }
            total += index.isMultiple(of: 2) ? digit : digit * 3
        }

        let checkDigit = (10 - (total % 10)) % 10
        guard let last = chars[12].wholeNumberValue else {
            return false
        }

        return checkDigit == last
    }
}

func dedupeIdentifiersPreservingOrder(_ identifiers: [Identifier]) -> [Identifier] {
    var seen = Set<String>()
    var ordered = [Identifier]()

    for identifier in identifiers {
        let key = "\(identifier.type.rawValue):\(identifier.value.lowercased())"
        if seen.insert(key).inserted {
            ordered.append(identifier)
        }
    }

    return ordered
}

private func makeStaticRegex(pattern: String, name: String) -> NSRegularExpression {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        fatalError("Invalid \(name) regex pattern: \(pattern)")
    }
    return regex
}
