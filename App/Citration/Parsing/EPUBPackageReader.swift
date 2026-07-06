import Foundation

// MARK: - EPUBPublication

struct EPUBPublication: Equatable {
    var rootDirectory: URL
    var packageDocumentURL: URL
    var initialDocumentURL: URL
    var title: String?
}

// MARK: - EPUBPackageReaderError

enum EPUBPackageReaderError: Error, LocalizedError {
    case missingUnzipTool
    case invalidArchive
    case unsafeArchiveEntry(String)
    case extractionFailed(String)
    case packageDocumentMissing
    case initialDocumentMissing

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .missingUnzipTool:
            "The system unzip tool is not available."
        case .invalidArchive:
            "The EPUB archive could not be read."
        case let .unsafeArchiveEntry(entry):
            "The EPUB archive contains an unsafe path: \(entry)"
        case let .extractionFailed(details):
            "The EPUB archive could not be unpacked: \(details)"
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
        unzipURL: URL = URL(fileURLWithPath: "/usr/bin/unzip"),
        fileManager: FileManager = .default
    ) {
        self.unpackRoot = unpackRoot
        self.unzipURL = unzipURL
        self.fileManager = fileManager
    }

    // MARK: Internal

    static func defaultUnpackRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-epub-reader", isDirectory: true)
    }

    func publication(from epubURL: URL) throws -> EPUBPublication {
        guard fileManager.isExecutableFile(atPath: unzipURL.path) else {
            throw EPUBPackageReaderError.missingUnzipTool
        }

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
    private let unzipURL: URL
    private let fileManager: FileManager

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
        guard
            let initialHref = initialDocumentHref(in: packageXML),
            let initialURL = try? resolvedURL(
                for: initialHref,
                relativeTo: packageDirectory,
                rootDirectory: rootDirectory
            ),
            fileManager.fileExists(atPath: initialURL.path)
        else {
            throw EPUBPackageReaderError.initialDocumentMissing
        }

        return EPUBPublication(
            rootDirectory: rootDirectory,
            packageDocumentURL: packageDocumentURL,
            initialDocumentURL: initialURL,
            title: publicationTitle(in: packageXML)
        )
    }

    private func archiveEntries(in epubURL: URL) throws -> [String] {
        let result = try runProcess(
            executableURL: unzipURL,
            arguments: ["-Z1", epubURL.path]
        )
        guard result.exitStatus == 0 else {
            throw EPUBPackageReaderError.invalidArchive
        }

        return result.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extract(_ epubURL: URL, to destinationURL: URL) throws {
        let result = try runProcess(
            executableURL: unzipURL,
            arguments: ["-q", "-o", epubURL.path, "-d", destinationURL.path]
        )
        guard result.exitStatus == 0 else {
            throw EPUBPackageReaderError.extractionFailed(result.errorOutput)
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

    private func initialDocumentHref(in packageXML: String) -> String? {
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
            manifest[id] = EPUBManifestItem(href: href, mediaType: attributes["media-type"])
        }

        for itemRef in allTags(matching: #"<itemref\b[^>]*>"#, in: packageXML) {
            let attributes = attributes(in: itemRef)
            guard
                attributes["linear"]?.lowercased() != "no",
                let idref = attributes["idref"],
                let item = manifest[idref],
                item.isReadableDocument
            else {
                continue
            }
            return item.href
        }

        return manifest.values.first { $0.isReadableDocument }?.href
    }

    private func publicationTitle(in packageXML: String) -> String? {
        firstMatch(
            pattern: #"<(?:[A-Za-z0-9_-]+:)?title\b[^>]*>(.*?)</(?:[A-Za-z0-9_-]+:)?title>"#,
            text: packageXML
        )?.decodedXMLEntities().bcCollapsedWhitespace().bcTrimmedNonEmpty
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
            values[match[1].lowercased()] = match[2].decodedXMLEntities()
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

    private func runProcess(
        executableURL: URL,
        arguments: [String]
    ) throws -> EPUBProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return EPUBProcessResult(
            exitStatus: process.terminationStatus,
            output: output,
            errorOutput: errorOutput
        )
    }
}

// MARK: - EPUBManifestItem

private struct EPUBManifestItem {
    var href: String
    var mediaType: String?

    var isReadableDocument: Bool {
        switch mediaType?.lowercased() {
        case "application/xhtml+xml",
             "text/html":
            true
        default:
            false
        }
    }
}

// MARK: - EPUBProcessResult

private struct EPUBProcessResult {
    var exitStatus: Int32
    var output: String
    var errorOutput: String
}

private extension String {
    func decodedXMLEntities() -> String {
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
