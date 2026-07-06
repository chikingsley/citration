@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - Factories

@MainActor
func makeAppModel(
    providers: [any MetadataProvider],
    pdfDOIExtractor: any PDFDOIExtracting = NullPDFDOIExtractor(),
    attachmentStore: LocalAttachmentStore? = nil
) -> AppModel {
    AppModel(
        store: InMemoryItemStore(),
        metadataRegistry: MetadataProviderRegistry(providers: providers),
        citationFormatter: StubCitationFormatter(),
        storageConnectors: [],
        pdfDOIExtractor: pdfDOIExtractor,
        attachmentStore: attachmentStore,
        annotationStore: makeAnnotationStore(),
        collectionStore: makeCollectionStore(),
        noteStore: makeNoteStore(),
        relationshipStore: makeRelationshipStore(),
        readerProgressStore: makeReaderProgressStore()
    )
}

func makeAnnotationStore() -> LocalAnnotationStore? {
    try? LocalAnnotationStore(
        storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-appmodel-annotations")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    )
}

func makeCollectionStore() -> LocalCollectionStore? {
    try? LocalCollectionStore(
        storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-appmodel-collections")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    )
}

func makeNoteStore() -> LocalNoteStore? {
    try? LocalNoteStore(
        storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-appmodel-notes")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    )
}

func makeRelationshipStore() -> LocalRelationshipStore? {
    try? LocalRelationshipStore(
        storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-appmodel-relationships")
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
