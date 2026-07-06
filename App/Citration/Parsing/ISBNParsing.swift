import CitrationCore
import Foundation

enum ISBNParsing {
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

    // MARK: Private

    private static let candidateRegex = makeStaticRegex(
        pattern: #"(?i)\b(?:isbn(?:-1[03])?\s*:?)?\s*((?:97[89][\d\-\s]{10,20})|(?:[\dX][\d\-\s]{8,20}))\b"#,
        name: "ISBN candidate"
    )

    private static func isValidISBN10(_ value: String) -> Bool {
        guard value.count == 10 else {
            return false
        }

        let chars = Array(value)
        var total = 0

        for index in 0 ..< 9 {
            guard let digit = chars[index].wholeNumberValue else {
                return false
            }
            total += (10 - index) * digit
        }

        let checksum: Int
        if chars[9] == "X" {
            checksum = 10
        } else if let digit = chars[9].wholeNumberValue {
            checksum = digit
        } else {
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

        for index in 0 ..< 12 {
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
