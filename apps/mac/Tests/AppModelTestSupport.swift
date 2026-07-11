@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - Factories

@MainActor
func makeAppModel(
    initialItems: [BCItem] = [],
    providers: [any MetadataProvider] = [NoopMetadataProvider()],
    pdfDOIExtractor: any PDFDOIExtracting = NullPDFDOIExtractor(),
    attachmentStore: LocalAttachmentStore? = nil,
    annotationStore: LocalAnnotationStore? = nil,
    readerProgressStore: LocalReaderProgressStore? = nil,
    ocrService: any OCRServicing = NullOCRService()
) -> AppModel {
    let database = makeDatabase()
    let persistence: CitrationLibraryStore
    do {
        persistence = try CitrationLibraryStore(
            database: database,
            attachmentsDirectory: makeTempDirectory().appending(path: "attachments", directoryHint: .isDirectory),
            initialItems: initialItems
        )
    } catch {
        fatalError("Unable to initialize the real GRDB AppModel test store: \(error)")
    }
    return AppModel(
        database: database,
        connectionManager: ZoteroConnectionManager(
            database: database,
            credentialStore: FileZoteroCredentialStore(
                fileURL: makeTempDirectory().appending(path: "zotero-device-api-key")
            )
        ),
        store: persistence,
        metadataRegistry: MetadataProviderRegistry(providers: providers),
        citationFormatter: StubCitationFormatter(),
        storageConnectors: [],
        attachmentStore: attachmentStore ?? persistence,
        annotationStore: annotationStore ?? persistence,
        collectionStore: persistence,
        noteStore: persistence,
        relationshipStore: persistence,
        readerProgressStore: readerProgressStore ?? persistence,
        pdfDOIExtractor: pdfDOIExtractor,
        ocrService: ocrService,
        openAlexAPIKeyStore: FileAPIKeyStore(
            fileURL: makeTempDirectory().appending(path: "openalex-api-key")
        ),
        ocrAPIKeyStore: FileAPIKeyStore(
            fileURL: makeTempDirectory().appending(path: "mistral-api-key")
        )
    )
}

func makeDatabase() -> CitrationDatabase {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "citration-appmodel-databases", directoryHint: .isDirectory)
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try CitrationDatabase(at: directory.appending(path: "library.sqlite"))
    } catch {
        fatalError("Unable to initialize test database: \(error)")
    }
}

// MARK: - NullOCRService

/// Default for tests: never configured, never touches the network.
struct NullOCRService: OCRServicing {
    func isConfigured() -> Bool {
        false
    }

    func recognizeText(from documentURL: URL) throws -> String {
        _ = documentURL
        throw OCRServiceError.notConfigured
    }
}

// MARK: - StubOCRService

/// Returns fixed markdown, recording nothing; lets tests exercise the
/// OCR enrichment path without the network.
struct StubOCRService: OCRServicing {
    let markdown: String

    func isConfigured() -> Bool {
        true
    }

    func recognizeText(from documentURL: URL) -> String {
        _ = documentURL
        return markdown
    }
}

func makeAnnotationStore() -> LocalAnnotationStore? {
    try? LocalAnnotationStore(
        storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-appmodel-annotations")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    )
}

func makeReaderProgressStore() -> LocalReaderProgressStore? {
    try? LocalReaderProgressStore(
        storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-appmodel-reader-progress")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    )
}

// MARK: - Fixtures

func makeTempDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("citration-appmodel-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func cleanupDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

func makeFile(named fileName: String, contents: Data, in directory: URL) throws -> URL {
    let fileURL = directory.appendingPathComponent(fileName)
    try contents.write(to: fileURL)
    return fileURL
}

func makeAttachment(itemID: UUID, fileName: String, contentType: String) -> LocalAttachment {
    LocalAttachment(
        itemID: itemID,
        fileName: fileName,
        objectKey: "\(itemID.uuidString)/\(fileName)",
        localURL: URL(fileURLWithPath: "/tmp/\(fileName)"),
        contentType: contentType,
        size: 128,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

// MARK: - Waiting

@MainActor
func waitUntil(
    timeout: TimeInterval = 2.0,
    pollInterval: UInt64 = 10_000_000,
    _ condition: @MainActor () -> Bool
) async throws {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollInterval)
    }
    Issue.record("Timed out waiting for condition")
}

// MARK: - StubMetadataProvider

struct StubMetadataProvider: MetadataProvider {
    let name: String = "stub-metadata"
    let records: [CanonicalMetadataRecord]
    let delayNanoseconds: UInt64

    func resolve(_ request: MetadataResolutionRequest) async -> [CanonicalMetadataRecord] {
        _ = request
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return records
    }
}

// MARK: - StubPDFDOIExtractor

struct StubPDFDOIExtractor: PDFDOIExtracting {
    let doi: String?

    func extractDOI(from pdfURL: URL) -> String? {
        _ = pdfURL
        return doi
    }
}

// MARK: - StubPDFCandidateExtractor

struct StubPDFCandidateExtractor: PDFDOIExtracting {
    let candidates: PDFMetadataCandidates

    func extractDOI(from pdfURL: URL) -> String? {
        _ = pdfURL
        return candidates.detectedDOI
    }

    func extractCandidates(from pdfURL: URL) -> PDFMetadataCandidates {
        _ = pdfURL
        return candidates
    }
}

// MARK: - SlowPDFExtractor

struct SlowPDFExtractor: PDFDOIExtracting {
    let delayNanoseconds: UInt64

    func extractDOI(from pdfURL: URL) async -> String? {
        _ = pdfURL
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return nil
    }
}

// MARK: - MetadataRequestRecorder

actor MetadataRequestRecorder {
    // MARK: Internal

    func append(_ request: MetadataResolutionRequest) {
        storedRequests.append(request)
    }

    func requests() -> [MetadataResolutionRequest] {
        storedRequests
    }

    // MARK: Private

    private var storedRequests: [MetadataResolutionRequest] = []
}

// MARK: - OrderedResolutionProvider

struct OrderedResolutionProvider: MetadataProvider {
    let name: String = "ordered-resolution"
    let recorder: MetadataRequestRecorder

    func resolve(_ request: MetadataResolutionRequest) async -> [CanonicalMetadataRecord] {
        await recorder.append(request)
        guard let first = request.identifiers.first else {
            return []
        }
        if first.type == .doi {
            return [
                CanonicalMetadataRecord(
                    title: "Resolved From DOI",
                    creators: [Creator(givenName: "Order", familyName: "Check")],
                    publicationYear: 2024,
                    itemType: .article,
                    identifiers: [Identifier(type: .doi, value: first.value)],
                    confidence: 0.95,
                    provenance: MetadataProvenance(providerName: name)
                )
            ]
        }
        return []
    }
}
