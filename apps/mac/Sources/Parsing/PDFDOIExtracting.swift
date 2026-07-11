import CitrationCore
import Foundation
import PDFKit

// MARK: - PDFMetadataCandidates

struct PDFMetadataCandidates {
    // MARK: Lifecycle

    init(identifiers: [Identifier] = [], titleHints: [String] = []) {
        self.identifiers = identifiers
        self.titleHints = titleHints
    }

    // MARK: Internal

    var identifiers: [Identifier]
    var titleHints: [String]

    var detectedDOI: String? {
        identifiers.first { $0.type == .doi }?.value
    }

    var isEmpty: Bool {
        identifiers.isEmpty && titleHints.isEmpty
    }
}

// MARK: - PDFDOIExtracting

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

// MARK: - PDFKitDOIExtractor

/// Extracts bibliographic identifiers from a PDF's text layer via PDFKit.
actor PDFKitDOIExtractor: PDFDOIExtracting {
    // MARK: Lifecycle

    init(
        verifyWithDOIResolver: Bool = false,
        session: URLSession = .shared
    ) {
        self.verifyWithDOIResolver = verifyWithDOIResolver
        self.session = session
    }

    // MARK: Internal

    /// Whether the document carries a usable text layer; scanned books
    /// come back false and are candidates for an OCR pass instead.
    nonisolated static func hasTextLayer(at pdfURL: URL, samplePages: Int = 5) -> Bool {
        guard let document = PDFDocument(url: pdfURL) else {
            return false
        }

        var characters = 0
        for index in 0 ..< min(document.pageCount, samplePages) {
            let text = document.page(at: index)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            characters += text.count
            if characters >= 40 {
                return true
            }
        }
        return false
    }

    nonisolated static func extractText(from pdfURL: URL) -> String? {
        guard let document = PDFDocument(url: pdfURL) else {
            return nil
        }

        var chunks = [String]()
        chunks.reserveCapacity(document.pageCount)

        for index in 0 ..< document.pageCount {
            if let pageString = document.page(at: index)?.string, !pageString.isEmpty {
                chunks.append(pageString)
            }
        }

        guard !chunks.isEmpty else {
            return nil
        }

        return chunks.joined(separator: "\n")
    }

    func extractDOI(from pdfURL: URL) async -> String? {
        let candidates = await extractCandidates(from: pdfURL)
        return candidates.detectedDOI
    }

    func extractCandidates(from pdfURL: URL) async -> PDFMetadataCandidates {
        guard pdfURL.pathExtension.lowercased() == "pdf" else {
            return PDFMetadataCandidates()
        }

        guard let text = Self.extractText(from: pdfURL) else {
            return PDFMetadataCandidates()
        }

        let identifiers = await orderedIdentifiers(in: text)
        guard !identifiers.isEmpty else {
            return PDFMetadataCandidates()
        }

        return PDFMetadataCandidates(identifiers: identifiers, titleHints: [])
    }

    /// Builds ordered identifier candidates from arbitrary extracted text
    /// (text layer or OCR output): arXiv first, then DOIs, then ISBNs.
    func orderedIdentifiers(in text: String) async -> [Identifier] {
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

    // MARK: Private

    private let verifyWithDOIResolver: Bool
    private let session: URLSession

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
            if let http = response as? HTTPURLResponse, (200 ..< 400).contains(http.statusCode) {
                return true
            }
        } catch {
            return false
        }

        return false
    }
}
