import Foundation

/// A local HTML snapshot with a restrictive policy injected before WebKit sees it.
struct CachedHTMLDocument: Equatable {
    // MARK: Lifecycle

    init(fileURL: URL) throws {
        var encoding: UInt = 0
        let source = try NSString(contentsOf: fileURL, usedEncoding: &encoding) as String
        html = Self.injectContentSecurityPolicy(into: source)
        baseURL = fileURL.deletingLastPathComponent()
    }

    // MARK: Internal

    static let contentSecurityPolicy = """
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; \
    img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; \
    media-src 'self' data:; object-src 'none'; frame-src 'none'; connect-src 'none'">
    """

    let html: String
    let baseURL: URL

    // MARK: Private

    private static func injectContentSecurityPolicy(into source: String) -> String {
        if let openingHeadEnd = endOfOpeningTag(named: "head", in: source) {
            var result = source
            result.insert(contentsOf: contentSecurityPolicy, at: openingHeadEnd)
            return result
        }
        if let openingHTMLEnd = endOfOpeningTag(named: "html", in: source) {
            var result = source
            result.insert(contentsOf: "<head>\(contentSecurityPolicy)</head>", at: openingHTMLEnd)
            return result
        }
        return "<!doctype html><html><head>\(contentSecurityPolicy)</head><body>\(source)</body></html>"
    }

    private static func endOfOpeningTag(named name: String, in source: String) -> String.Index? {
        var searchRange = source.startIndex ..< source.endIndex
        while
            let tagStart = source.range(
                of: "<\(name)",
                options: .caseInsensitive,
                range: searchRange
            )
        {
            let boundary = tagStart.upperBound
            let isExactTag = boundary == source.endIndex
                || source[boundary] == ">"
                || source[boundary] == "/"
                || source[boundary].isWhitespace
            if
                isExactTag,
                let tagEnd = source[tagStart.lowerBound...].firstIndex(of: ">")
            {
                return source.index(after: tagEnd)
            }
            searchRange = boundary ..< source.endIndex
        }
        return nil
    }
}
