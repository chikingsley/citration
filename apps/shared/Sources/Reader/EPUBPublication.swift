import Foundation

// MARK: - EPUBPublication

struct EPUBPublication: Equatable {
    var rootDirectory: URL
    var packageDocumentURL: URL
    var initialDocumentURL: URL
    var title: String?
    var readingOrder: [EPUBSpineItem]
    var tableOfContents: [EPUBNavigationItem]

    func readingOrderIndex(forCFI cfi: String) -> Int? {
        readingOrder.firstIndex { cfi.hasPrefix("epubcfi(\($0.cfiBase)!") }
    }

    func search(_ query: String, limit: Int = 50) -> [EPUBSearchResult] {
        let normalizedQuery = query.bcCollapsedWhitespace().bcTrimmedNonEmpty
        guard let normalizedQuery else {
            return []
        }

        var results = [EPUBSearchResult]()
        for (index, item) in readingOrder.enumerated() {
            let text = (try? String(contentsOf: item.documentURL, encoding: .utf8))?.epubPlainText ?? ""
            guard
                let matchRange = text.range(
                    of: normalizedQuery,
                    options: [.caseInsensitive, .diacriticInsensitive]
                )
            else {
                continue
            }
            let offset = text.distance(from: text.startIndex, to: matchRange.lowerBound)
            results.append(
                EPUBSearchResult(
                    readingOrderIndex: index,
                    chapterTitle: item.title,
                    query: normalizedQuery,
                    characterOffset: offset,
                    excerpt: text.epubExcerpt(around: matchRange)
                )
            )
            if results.count == limit {
                break
            }
        }
        return results
    }
}

// MARK: - EPUBSpineItem

struct EPUBSpineItem: Equatable, Identifiable {
    var idref: String
    var href: String
    var documentURL: URL
    var spineNodeIndex: Int
    var spineIndex: Int
    var title: String

    var id: String {
        idref
    }

    var cfiBase: String {
        "/\((spineNodeIndex + 1) * 2)/\((spineIndex + 1) * 2)"
    }
}

// MARK: - EPUBNavigationItem

struct EPUBNavigationItem: Equatable, Identifiable {
    var title: String
    var readingOrderIndex: Int
    var fragment: String?

    var id: String {
        "\(readingOrderIndex):\(fragment ?? ""):\(title)"
    }
}

// MARK: - EPUBSearchResult

struct EPUBSearchResult: Equatable, Identifiable {
    var readingOrderIndex: Int
    var chapterTitle: String
    var query: String
    var characterOffset: Int
    var excerpt: String

    var id: String {
        "\(readingOrderIndex):\(characterOffset):\(query)"
    }
}

extension String {
    var epubPlainText: String {
        replacingOccurrences(of: #"<script\b[^>]*>.*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style\b[^>]*>.*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .epubDecodedXMLEntities()
            .bcCollapsedWhitespace()
    }

    func epubExcerpt(around range: Range<String.Index>, radius: Int = 70) -> String {
        let start = index(range.lowerBound, offsetBy: -radius, limitedBy: startIndex) ?? startIndex
        let end = index(range.upperBound, offsetBy: radius, limitedBy: endIndex) ?? endIndex
        let prefix = start == startIndex ? "" : "…"
        let suffix = end == endIndex ? "" : "…"
        let excerpt = (self as NSString).substring(with: NSRange(start ..< end, in: self))
        return prefix + excerpt.bcCollapsedWhitespace() + suffix
    }

    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let text = self as NSString
        guard let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: text.length)), match.numberOfRanges > 1 else {
            return nil
        }
        return text.substring(with: match.range(at: 1))
    }

    func epubDecodedXMLEntities() -> String {
        var value = self
        let replacements = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
        ]
        for (entity, replacement) in replacements {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
    }
}
