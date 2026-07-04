import Foundation
import CitrationCore
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

        if let envPath = ProcessInfo.processInfo.environment["BETTERCITE_MUTOOL_PATH"],
           !envPath.isEmpty,
           isExecutable(atPath: envPath, fileManager: fileManager) {
            return URL(fileURLWithPath: envPath)
        }

        if let bundledTool = Bundle.main.url(forResource: "mutool", withExtension: nil, subdirectory: "Tools"),
           isExecutable(atPath: bundledTool.path, fileManager: fileManager) {
            return bundledTool
        }

        if let bundledTool = Bundle.main.url(forResource: "mutool", withExtension: nil),
           isExecutable(atPath: bundledTool.path, fileManager: fileManager) {
            return bundledTool
        }

        for path in ["/opt/homebrew/bin/mutool", "/usr/local/bin/mutool", "/usr/bin/mutool"]
            where isExecutable(atPath: path, fileManager: fileManager) {
            return URL(fileURLWithPath: path)
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
        if allowPDFKitFallback,
           let text = extractTextWithPDFKit(from: pdfURL) {
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
            guard await verifyDOI(candidate) else {
                continue
            }
            accepted.append(candidate)
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
            .appendingPathComponent("citration-mupdf-\(UUID().uuidString)")
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
