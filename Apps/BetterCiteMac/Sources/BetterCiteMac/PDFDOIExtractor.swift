import Foundation
import BCCommon
#if canImport(PDFKit)
import PDFKit
#endif

struct PDFMetadataCandidates: Sendable {
    var identifiers: [Identifier]
    var titleHints: [String]

    init(identifiers: [Identifier] = [], titleHints: [String] = []) {
        self.identifiers = identifiers
        self.titleHints = titleHints
    }

    var detectedDOI: String? {
        identifiers.first { $0.type == .doi }?.value
    }

    var isEmpty: Bool {
        identifiers.isEmpty && titleHints.isEmpty
    }
}

protocol PDFDOIExtracting: Sendable {
    func extractDOI(from pdfURL: URL) async -> String?
    func extractCandidates(from pdfURL: URL) async -> PDFMetadataCandidates
}

extension PDFDOIExtracting {
    func extractCandidates(from pdfURL: URL) async -> PDFMetadataCandidates {
        guard let doi = await extractDOI(from: pdfURL) else {
            return PDFMetadataCandidates()
        }
        return PDFMetadataCandidates(
            identifiers: [Identifier(type: .doi, value: doi)],
            titleHints: []
        )
    }
}

struct NullPDFDOIExtractor: PDFDOIExtracting {
    func extractDOI(from pdfURL: URL) async -> String? {
        _ = pdfURL
        return nil
    }

    func extractCandidates(from pdfURL: URL) async -> PDFMetadataCandidates {
        _ = pdfURL
        return PDFMetadataCandidates()
    }
}

actor MuPDFDOIExtractor: PDFDOIExtracting {
    private static let drawTimeoutSeconds: TimeInterval = 20
    private let executableURL: URL?
    private let allowPDFKitFallback: Bool
    private let verifyWithDOIResolver: Bool
    private let session: URLSession

    init(
        executableURL: URL? = MuPDFDOIExtractor.defaultExecutableURL(),
        allowPDFKitFallback: Bool = true,
        verifyWithDOIResolver: Bool = false,
        session: URLSession = .shared
    ) {
        self.executableURL = executableURL
        self.allowPDFKitFallback = allowPDFKitFallback
        self.verifyWithDOIResolver = verifyWithDOIResolver
        self.session = session
    }

    nonisolated static func defaultExecutableURL() -> URL? {
        let fileManager = FileManager.default

        if
            let envPath = ProcessInfo.processInfo.environment["BETTERCITE_MUTOOL_PATH"],
            !envPath.isEmpty,
            isExecutable(atPath: envPath, fileManager: fileManager)
        {
            return URL(fileURLWithPath: envPath)
        }

        if
            let bundledTool = Bundle.main.url(forResource: "mutool", withExtension: nil, subdirectory: "Tools"),
            isExecutable(atPath: bundledTool.path, fileManager: fileManager)
        {
            return bundledTool
        }

        if
            let bundledTool = Bundle.main.url(forResource: "mutool", withExtension: nil),
            isExecutable(atPath: bundledTool.path, fileManager: fileManager)
        {
            return bundledTool
        }

        for path in ["/opt/homebrew/bin/mutool", "/usr/local/bin/mutool", "/usr/bin/mutool"] {
            if isExecutable(atPath: path, fileManager: fileManager) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    nonisolated private static func isExecutable(atPath path: String, fileManager: FileManager) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }

    func extractDOI(from pdfURL: URL) async -> String? {
        let candidates = await extractCandidates(from: pdfURL)
        return candidates.detectedDOI
    }

    func extractCandidates(from pdfURL: URL) async -> PDFMetadataCandidates {
        guard pdfURL.pathExtension.lowercased() == "pdf" else {
            return PDFMetadataCandidates()
        }

        if let result = await extractCandidatesWithMuPDFStructuredText(from: pdfURL) {
            return result
        }

        if let text = try? extractTextWithMuPDF(from: pdfURL) {
            let identifiers = await orderedIdentifiers(in: text)
            if !identifiers.isEmpty {
                return PDFMetadataCandidates(identifiers: identifiers, titleHints: [])
            }
        }

        #if canImport(PDFKit)
        if
            allowPDFKitFallback,
            let text = extractTextWithPDFKit(from: pdfURL)
        {
            let identifiers = await orderedIdentifiers(in: text)
            if !identifiers.isEmpty {
                return PDFMetadataCandidates(identifiers: identifiers, titleHints: [])
            }
        }
        #endif

        return PDFMetadataCandidates()
    }

    private func extractCandidatesWithMuPDFStructuredText(from pdfURL: URL) async -> PDFMetadataCandidates? {
        guard let document = try? extractStructuredTextWithMuPDF(from: pdfURL) else {
            return nil
        }

        let text = document.allText
        let identifiers = await orderedIdentifiers(in: text)
        let titleHints = titleHints(from: document)

        if identifiers.isEmpty, titleHints.isEmpty {
            return nil
        }

        return PDFMetadataCandidates(
            identifiers: identifiers,
            titleHints: titleHints
        )
    }

    private func orderedIdentifiers(in text: String) async -> [Identifier] {
        var identifiers = [Identifier]()

        for arXiv in ArXivParsing.candidates(in: text) {
            identifiers.append(Identifier(type: .arxiv, value: arXiv))
        }

        for doi in await acceptableDOICandidates(in: text) {
            identifiers.append(Identifier(type: .doi, value: doi))
        }

        for isbn in ISBNParsing.candidates(in: text) {
            identifiers.append(Identifier(type: .isbn, value: isbn))
        }

        return dedupeIdentifiersPreservingOrder(identifiers)
    }

    private func acceptableDOICandidates(in text: String) async -> [String] {
        let candidates = DOIParsing.candidates(in: text)
        guard verifyWithDOIResolver else {
            return candidates
        }

        var accepted = [String]()
        for candidate in candidates.prefix(5) {
            if await verifyDOI(candidate) {
                accepted.append(candidate)
            }
        }
        return accepted
    }

    private func extractTextWithMuPDF(from pdfURL: URL) throws -> String {
        let data = try runMuPDFDraw(
            format: "txt",
            sourcePDFURL: pdfURL,
            pageRange: nil,
            outputExtension: "txt"
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func extractStructuredTextWithMuPDF(from pdfURL: URL) throws -> MuPDFStructuredDocument {
        let data = try runMuPDFDraw(
            format: "stext.json",
            sourcePDFURL: pdfURL,
            pageRange: "1-5",
            outputExtension: "json"
        )
        return try JSONDecoder().decode(MuPDFStructuredDocument.self, from: data)
    }

    private func runMuPDFDraw(
        format: String,
        sourcePDFURL: URL,
        pageRange: String?,
        outputExtension: String
    ) throws -> Data {
        guard let executableURL else {
            throw CocoaError(.executableNotLoadable)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("better-cite-mupdf-\(UUID().uuidString)")
            .appendingPathExtension(outputExtension)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        var arguments = ["draw", "-F", format, "-o", outputURL.path, sourcePDFURL.path]
        if let pageRange {
            arguments.append(pageRange)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        // Keep stderr drained to avoid potential process blocking.
        let stderr = Pipe()
        process.standardError = stderr

        let didExit = try runProcessAndWait(
            process,
            timeout: Self.drawTimeoutSeconds
        )
        guard didExit, process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad)
        }

        return (try? Data(contentsOf: outputURL, options: .mappedIfSafe)) ?? Data()
    }

    private func runProcessAndWait(_ process: Process, timeout: TimeInterval) throws -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        try process.run()
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .success {
            return true
        }

        if process.isRunning {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 1)
        }
        return false
    }

    #if canImport(PDFKit)
    private nonisolated func extractTextWithPDFKit(from pdfURL: URL) -> String? {
        guard let document = PDFDocument(url: pdfURL) else {
            return nil
        }

        var chunks = [String]()
        chunks.reserveCapacity(document.pageCount)

        for index in 0..<document.pageCount {
            if let pageString = document.page(at: index)?.string, !pageString.isEmpty {
                chunks.append(pageString)
            }
        }

        guard !chunks.isEmpty else {
            return nil
        }

        return chunks.joined(separator: "\n")
    }
    #endif

    private func verifyDOI(_ doi: String) async -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/()")
        let encoded = doi.addingPercentEncoding(withAllowedCharacters: allowed) ?? doi
        guard let url = URL(string: "https://doi.org/\(encoded)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                return true
            }
        }
        catch {
            return false
        }

        return false
    }
}

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

private struct MuPDFStructuredDocument: Decodable {
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

private struct MuPDFStructuredPage: Decodable {
    let blocks: [MuPDFStructuredBlock]
}

private struct MuPDFStructuredBlock: Decodable {
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

private struct MuPDFStructuredLine: Decodable {
    let text: String?
    let x: Double?
    let y: Double?
    let font: MuPDFStructuredFont?
}

private struct MuPDFStructuredFont: Decodable {
    let size: Double?
}

private func dedupeIdentifiersPreservingOrder(_ identifiers: [Identifier]) -> [Identifier] {
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

private func titleHints(from document: MuPDFStructuredDocument) -> [String] {
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
    if lower.hasPrefix("doi:") || lower.contains("arxiv:") || lower.hasPrefix("http://") || lower.hasPrefix("https://") {
        return false
    }
    if DOIParsing.normalizeCandidate(trimmed) != nil || ArXivParsing.normalizeCandidate(trimmed) != nil || ISBNParsing.normalizeCandidate(trimmed) != nil {
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

private func makeStaticRegex(pattern: String, name: String) -> NSRegularExpression {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        fatalError("Invalid \(name) regex pattern: \(pattern)")
    }
    return regex
}
