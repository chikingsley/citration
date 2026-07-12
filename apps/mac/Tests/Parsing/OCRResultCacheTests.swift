@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - OCRResultCacheTests

@Suite("OCR result cache")
struct OCRResultCacheTests {
    @Test("stores and reloads by content hash")
    func roundTrip() {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }
        let cache = OCRResultCache(directory: directory)
        let hash = OCRResultCache.contentHash(of: Data("pdf-bytes".utf8))

        #expect(cache.load(contentHash: hash) == nil)
        cache.store("# Recognized\n", contentHash: hash)
        #expect(cache.load(contentHash: hash) == "# Recognized\n")
    }

    @Test("cached document never reaches the network")
    func cacheHitSkipsNetworkAndKey() async throws {
        let directory = makeTempDirectory()
        defer { cleanupDirectory(directory) }

        let document = directory.appendingPathComponent("scan.pdf")
        try Data("fake-scanned-pdf".utf8).write(to: document)
        let hash = OCRResultCache.contentHash(of: Data("fake-scanned-pdf".utf8))

        let cache = OCRResultCache(directory: directory)
        cache.store("cached ocr output\n", contentHash: hash)

        // No API key anywhere: a cache miss would throw notConfigured.
        let service = MistralOCRService(
            keyStore: FileAPIKeyStore(fileURL: directory.appendingPathComponent("missing-api-key")),
            cache: cache
        )
        let text = try await service.recognizeText(from: document)
        #expect(text == "cached ocr output\n")
    }
}

// MARK: - OCRImportFlowTests

@Suite("OCR import flow")
@MainActor
struct OCRImportFlowTests {
    @Test("captured OCR result enriches a real scanned book through the production service")
    func capturedOCRResultEnrichesRealScannedBook() async throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let attachmentStore = try LocalAttachmentStore(
            baseDirectory: tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        )

        let scannedPDF = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/kabul-persian-scanned.pdf")
        let markdown = try String(
            contentsOf: scannedPDF.deletingPathExtension().appendingPathExtension("ocr.md"),
            encoding: .utf8
        )
        let pdfData = try Data(contentsOf: scannedPDF)
        let cache = OCRResultCache(directory: tempDirectory.appendingPathComponent("ocr-cache", isDirectory: true))
        cache.store(markdown, contentHash: OCRResultCache.contentHash(of: pdfData))
        let keyStore = FileAPIKeyStore(fileURL: tempDirectory.appendingPathComponent("mistral-api-key"))
        await keyStore.saveAPIKey("cached-result")
        let service = MistralOCRService(
            keyStore: keyStore,
            cache: cache
        )

        let model = makeAppModel(
            pdfDOIExtractor: PDFKitDOIExtractor(),
            attachmentStore: attachmentStore,
            ocrService: service
        )
        await model.refreshItems()

        model.importer.importAttachments(urls: [scannedPDF], mode: .createNewItemPerFile)
        try await waitUntil(timeout: 5.0) {
            model.items.first?.title == "PERSIAN AN INTRODUCTION TO COLLOQUIAL KABUL PERSIAN"
        }

        #expect(model.items.count == 1)
        #expect(model.items.first?.identifiers.isEmpty == true)
    }
}
