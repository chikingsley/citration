@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - ImportMetadataFallbackTests

@Suite("Import Metadata Fallback")
@MainActor
struct ImportMetadataFallbackTests {
    @Test("import falls back to filename title metadata search")
    func importFallsBackToFilenameTitleMetadataSearch() async throws {
        let recorder = TitleMetadataRequestRecorder()
        let provider = TitleResolutionProvider(
            recorder: recorder,
            query: "attention is all you need"
        )

        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let sourceFile = try makeFile(
            named: "attention-is-all-you-need.pdf",
            contents: Data("dummy".utf8),
            in: tempDirectory
        )
        let attachmentsDirectory = tempDirectory.appendingPathComponent("attachments", isDirectory: true)
        let attachmentStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)

        let model = makeModel(
            providers: [provider],
            attachmentStore: attachmentStore
        )
        await model.refreshItems()

        model.importAttachments(urls: [sourceFile], mode: .createNewItemPerFile)
        try await waitUntil(timeout: 3.0) {
            model.items.first?.title == "Resolved From Filename"
        }

        let requests = await recorder.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.identifiers.isEmpty == true)
        #expect(requests.first?.freeTextQuery == "attention is all you need")
        #expect(model.items.first?.creators.first?.displayName == "Title Match")
    }
}

private extension ImportMetadataFallbackTests {
    func makeModel(
        providers: [any MetadataProvider],
        attachmentStore: LocalAttachmentStore
    ) -> AppModel {
        AppModel(
            store: InMemoryItemStore(),
            metadataRegistry: MetadataProviderRegistry(providers: providers),
            citationFormatter: StubCitationFormatter(),
            storageConnectors: [],
            pdfDOIExtractor: NullPDFDOIExtractor(),
            attachmentStore: attachmentStore,
            annotationStore: makeAnnotationStore(),
            collectionStore: makeCollectionStore(),
            noteStore: makeNoteStore(),
            relationshipStore: makeRelationshipStore(),
            readerProgressStore: makeReaderProgressStore()
        )
    }

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

    func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-import-metadata-fallback-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func makeFile(named fileName: String, contents: Data, in directory: URL) throws -> URL {
        let fileURL = directory.appendingPathComponent(fileName)
        try contents.write(to: fileURL)
        return fileURL
    }

    func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeAnnotationStore() -> LocalAnnotationStore? {
        try? LocalAnnotationStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-import-title-annotations")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeCollectionStore() -> LocalCollectionStore? {
        try? LocalCollectionStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-import-title-collections")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeNoteStore() -> LocalNoteStore? {
        try? LocalNoteStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-import-title-notes")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeRelationshipStore() -> LocalRelationshipStore? {
        try? LocalRelationshipStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-import-title-relationships")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeReaderProgressStore() -> LocalReaderProgressStore? {
        try? LocalReaderProgressStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-import-title-reader-progress")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }
}

// MARK: - TitleMetadataRequestRecorder

private actor TitleMetadataRequestRecorder {
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

// MARK: - TitleResolutionProvider

private struct TitleResolutionProvider: MetadataProvider {
    let name: String = "title-resolution"
    let recorder: TitleMetadataRequestRecorder
    let query: String

    func resolve(_ request: MetadataResolutionRequest) async -> [CanonicalMetadataRecord] {
        await recorder.append(request)
        guard request.identifiers.isEmpty, request.freeTextQuery == query else {
            return []
        }

        return [
            CanonicalMetadataRecord(
                title: "Resolved From Filename",
                creators: [Creator(givenName: "Title", familyName: "Match")],
                publicationYear: 2017,
                itemType: .article,
                confidence: 0.75,
                provenance: MetadataProvenance(providerName: name)
            )
        ]
    }
}
