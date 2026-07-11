import Foundation
import ZIPFoundation

// MARK: - EPUBPackageReaderError

enum EPUBPackageReaderError: Error, LocalizedError {
    case invalidArchive
    case unsafeArchiveEntry(String)
    case packageDocumentMissing
    case initialDocumentMissing

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            "The EPUB archive could not be read."
        case let .unsafeArchiveEntry(entry):
            "The EPUB archive contains an unsafe path: \(entry)"
        case .packageDocumentMissing:
            "The EPUB package document could not be found."
        case .initialDocumentMissing:
            "The EPUB reading order could not be resolved."
        }
    }
}

// MARK: - EPUBPackageReader

struct EPUBPackageReader {
    // MARK: Lifecycle

    init(
        unpackRoot: URL = Self.defaultUnpackRoot(),
        fileManager: FileManager = .default
    ) {
        self.unpackRoot = unpackRoot
        self.fileManager = fileManager
    }

    // MARK: Internal

    static func defaultUnpackRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-epub-reader", isDirectory: true)
    }

    func publication(from epubURL: URL) throws -> EPUBPublication {
        let entries = try archiveEntries(in: epubURL)
        guard !entries.isEmpty else {
            throw EPUBPackageReaderError.invalidArchive
        }

        for entry in entries {
            try validateArchiveEntry(entry)
        }

        let rootDirectory = unpackRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        do {
            try extract(epubURL, to: rootDirectory)
            return try publication(in: rootDirectory)
        } catch {
            try? fileManager.removeItem(at: rootDirectory)
            throw error
        }
    }

    // MARK: Private

    private let unpackRoot: URL
    private let fileManager: FileManager
}

private extension EPUBPackageReader {
    private func publication(in rootDirectory: URL) throws -> EPUBPublication {
        let containerURL = rootDirectory
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")

        guard
            let containerXML = try? String(contentsOf: containerURL, encoding: .utf8),
            let packagePath = firstAttribute(
                named: "full-path",
                inFirstTagMatching: #"<rootfile\b[^>]*>"#,
                text: containerXML
            )
        else {
            throw EPUBPackageReaderError.packageDocumentMissing
        }

        let packageDocumentURL = try resolvedURL(
            for: packagePath,
            relativeTo: rootDirectory,
            rootDirectory: rootDirectory
        )
        guard fileManager.fileExists(atPath: packageDocumentURL.path) else {
            throw EPUBPackageReaderError.packageDocumentMissing
        }

        let packageXML = try String(contentsOf: packageDocumentURL, encoding: .utf8)
        let packageDirectory = packageDocumentURL.deletingLastPathComponent()
        let manifest = manifest(in: packageXML)
        let spineNodeIndex = spineNodeIndex(in: packageXML)
        let readingOrder = try readingOrder(
            in: packageXML,
            manifest: manifest,
            spineNodeIndex: spineNodeIndex,
            packageDirectory: packageDirectory,
            rootDirectory: rootDirectory
        )
        guard let initialURL = readingOrder.first?.documentURL else {
            throw EPUBPackageReaderError.initialDocumentMissing
        }

        let tableOfContents = try tableOfContents(
            manifest: manifest,
            readingOrder: readingOrder,
            packageDirectory: packageDirectory,
            rootDirectory: rootDirectory
        )

        return EPUBPublication(
            rootDirectory: rootDirectory,
            packageDocumentURL: packageDocumentURL,
            initialDocumentURL: initialURL,
            title: publicationTitle(in: packageXML),
            readingOrder: readingOrder,
            tableOfContents: tableOfContents
        )
    }

    private func archiveEntries(in epubURL: URL) throws -> [String] {
        let archive: Archive
        do {
            archive = try Archive(url: epubURL, accessMode: .read)
        } catch {
            throw EPUBPackageReaderError.invalidArchive
        }
        return archive.map(\.path)
    }

    private func extract(_ epubURL: URL, to destinationURL: URL) throws {
        let archive: Archive
        do {
            archive = try Archive(url: epubURL, accessMode: .read)
        } catch {
            throw EPUBPackageReaderError.invalidArchive
        }
        for entry in archive {
            try validateArchiveEntry(entry.path)
            guard entry.type != .symlink else {
                throw EPUBPackageReaderError.unsafeArchiveEntry(entry.path)
            }
            let destination = try resolvedURL(
                for: entry.path,
                relativeTo: destinationURL,
                rootDirectory: destinationURL
            )
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try archive.extract(entry, to: destination)
        }
    }

    private func validateArchiveEntry(_ entry: String) throws {
        if entry.hasPrefix("/") || entry.hasPrefix("\\") {
            throw EPUBPackageReaderError.unsafeArchiveEntry(entry)
        }

        let components = entry
            .split { $0 == "/" || $0 == "\\" }
            .map(String.init)

        if components.contains(where: { $0 == ".." }) {
            throw EPUBPackageReaderError.unsafeArchiveEntry(entry)
        }
    }

    private func manifest(in packageXML: String) -> [String: EPUBManifestItem] {
        let manifestItems = allTags(matching: #"<item\b[^>]*>"#, in: packageXML)
        var manifest = [String: EPUBManifestItem]()

        for tag in manifestItems {
            let attributes = attributes(in: tag)
            guard
                let id = attributes["id"],
                let href = attributes["href"],
                manifest[id] == nil
            else {
                continue
            }
            let properties = Set(
                (attributes["properties"] ?? "")
                    .split(whereSeparator: \.isWhitespace)
                    .map { $0.lowercased() }
            )
            manifest[id] = EPUBManifestItem(
                href: href,
                mediaType: attributes["media-type"],
                properties: properties
            )
        }

        return manifest
    }

    private func readingOrder(
        in packageXML: String,
        manifest: [String: EPUBManifestItem],
        spineNodeIndex: Int,
        packageDirectory: URL,
        rootDirectory: URL
    ) throws -> [EPUBSpineItem] {
        var readingOrder = [EPUBSpineItem]()
        for (spineIndex, itemRef) in allTags(matching: #"<itemref\b[^>]*>"#, in: packageXML).enumerated() {
            let attributes = attributes(in: itemRef)
            guard
                attributes["linear"]?.lowercased() != "no",
                let idref = attributes["idref"],
                let item = manifest[idref],
                item.isReadableDocument
            else {
                continue
            }
            let documentURL = try resolvedURL(
                for: item.href,
                relativeTo: packageDirectory,
                rootDirectory: rootDirectory
            )
            guard fileManager.fileExists(atPath: documentURL.path) else {
                continue
            }
            readingOrder.append(
                EPUBSpineItem(
                    idref: idref,
                    href: item.href,
                    documentURL: documentURL,
                    spineNodeIndex: spineNodeIndex,
                    spineIndex: spineIndex,
                    title: documentTitle(at: documentURL) ?? documentURL.deletingPathExtension().lastPathComponent
                )
            )
        }
        return readingOrder
    }

    private func tableOfContents(
        manifest: [String: EPUBManifestItem],
        readingOrder: [EPUBSpineItem],
        packageDirectory: URL,
        rootDirectory: URL
    ) throws -> [EPUBNavigationItem] {
        guard
            let navigation = manifest.values.first(where: { $0.properties.contains("nav") })
            ?? manifest.values.first(where: \.isNCX)
        else {
            return []
        }
        let navigationURL = try resolvedURL(
            for: navigation.href,
            relativeTo: packageDirectory,
            rootDirectory: rootDirectory
        )
        guard let markup = try? String(contentsOf: navigationURL, encoding: .utf8) else {
            return []
        }

        var items = [EPUBNavigationItem]()
        for (label, href) in navigationEntries(in: markup, isNCX: navigation.isNCX) {
            let pieces = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            guard let hrefPath = pieces.first.map(String.init) else {
                continue
            }
            let destinationURL = try resolvedURL(
                for: hrefPath,
                relativeTo: navigationURL.deletingLastPathComponent(),
                rootDirectory: rootDirectory
            )
            guard let readingOrderIndex = readingOrder.firstIndex(where: { $0.documentURL == destinationURL }) else {
                continue
            }
            let fragment = pieces.count == 2 ? String(pieces[1]) : nil
            items.append(
                EPUBNavigationItem(
                    title: label,
                    readingOrderIndex: readingOrderIndex,
                    fragment: fragment?.removingPercentEncoding ?? fragment
                )
            )
        }
        return items
    }

    private func navigationEntries(in markup: String, isNCX: Bool) -> [(String, String)] {
        if isNCX {
            let pattern = #"<text\b[^>]*>(.*?)</text>\s*</navLabel>\s*<content\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*/?>"#
            return matches(pattern: pattern, text: markup).compactMap { match in
                guard match.count == 3, let label = match[1].epubPlainText.bcTrimmedNonEmpty else {
                    return nil
                }
                return (label, match[2].epubDecodedXMLEntities())
            }
        }
        return allTags(matching: #"<a\b[^>]*>.*?</a>"#, in: markup).compactMap { anchor in
            guard
                let href = firstAttribute(named: "href", inFirstTagMatching: #"<a\b[^>]*>"#, text: anchor),
                let label = firstMatch(pattern: #"<a\b[^>]*>(.*?)</a>"#, text: anchor)?
                    .epubPlainText.bcTrimmedNonEmpty
            else {
                return nil
            }
            return (label, href)
        }
    }

    private func publicationTitle(in packageXML: String) -> String? {
        firstMatch(
            pattern: #"<(?:[A-Za-z0-9_-]+:)?title\b[^>]*>(.*?)</(?:[A-Za-z0-9_-]+:)?title>"#,
            text: packageXML
        )?.epubDecodedXMLEntities().bcCollapsedWhitespace().bcTrimmedNonEmpty
    }

    private func spineNodeIndex(in packageXML: String) -> Int {
        guard let data = packageXML.data(using: .utf8) else {
            return 2
        }
        let delegate = EPUBSpineIndexParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        return parser.parse() ? delegate.spineNodeIndex ?? 2 : 2
    }

    private func documentTitle(at documentURL: URL) -> String? {
        guard let markup = try? String(contentsOf: documentURL, encoding: .utf8) else {
            return nil
        }
        return firstMatch(pattern: #"<title\b[^>]*>(.*?)</title>"#, text: markup)?
            .epubPlainText.bcTrimmedNonEmpty
    }

    private func resolvedURL(
        for path: String,
        relativeTo baseURL: URL,
        rootDirectory: URL
    ) throws -> URL {
        let decodedPath = path.removingPercentEncoding ?? path
        guard !decodedPath.hasPrefix("/") else {
            throw EPUBPackageReaderError.unsafeArchiveEntry(path)
        }

        let url = baseURL
            .appendingPathComponent(decodedPath)
            .standardizedFileURL
        let rootPath = rootDirectory.standardizedFileURL.path
        guard url.path == rootPath || url.path.hasPrefix(rootPath + "/") else {
            throw EPUBPackageReaderError.unsafeArchiveEntry(path)
        }
        return url
    }

    private func firstAttribute(
        named name: String,
        inFirstTagMatching pattern: String,
        text: String
    ) -> String? {
        guard let tag = allTags(matching: pattern, in: text).first else {
            return nil
        }
        return attributes(in: tag)[name]
    }

    private func attributes(in tag: String) -> [String: String] {
        var values = [String: String]()
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*["']([^"']*)["']"#
        for match in matches(pattern: pattern, text: tag) {
            guard match.count == 3 else {
                continue
            }
            values[match[1].lowercased()] = match[2].epubDecodedXMLEntities()
        }
        return values
    }

    private func allTags(matching pattern: String, in text: String) -> [String] {
        matches(pattern: pattern, text: text).compactMap(\.first)
    }

    private func firstMatch(pattern: String, text: String) -> String? {
        matches(pattern: pattern, text: text).first?.dropFirst().first
    }

    private func matches(pattern: String, text: String) -> [[String]] {
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map { match in
            (0 ..< match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else {
                    return nil
                }
                return nsText.substring(with: range)
            }
        }
    }
}

// MARK: - EPUBManifestItem

private struct EPUBManifestItem {
    var href: String
    var mediaType: String?
    var properties: Set<String>

    var isReadableDocument: Bool {
        switch mediaType?.lowercased() {
        case "application/xhtml+xml",
             "text/html":
            true
        default:
            false
        }
    }

    var isNCX: Bool {
        mediaType?.lowercased() == "application/x-dtbncx+xml"
    }
}
