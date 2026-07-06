@testable import Citration
import CitrationCore
import Foundation
import Testing

// MARK: - ReaderAnnotationTests

@Suite("Reader Annotations")
@MainActor
struct ReaderAnnotationTests {
    @Test("addReaderNote persists note for active attachment")
    func addReaderNotePersistsNoteForActiveAttachment() async throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let annotationStore = try LocalAnnotationStore(
            storeURL: tempDirectory.appendingPathComponent("annotations.json")
        )
        let attachment = makeAttachment(
            itemID: UUID(),
            fileName: "reader.pdf",
            contentType: "application/pdf"
        )
        let model = makeModel(annotationStore: annotationStore)

        model.openReader(for: attachment)
        model.readerNoteDraft = "  Remember this argument  "
        model.addReaderNote()
        try await waitUntil { model.activeReaderAnnotations.count == 1 }

        #expect(model.readerNoteDraft.isEmpty)
        #expect(model.activeReaderAnnotations.first?.note == "Remember this argument")
        #expect(model.statusMessage == "Added note")
    }

    @Test("addReaderNote rejects empty note")
    func addReaderNoteRejectsEmptyNote() throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }
        let annotationStore = try LocalAnnotationStore(
            storeURL: tempDirectory.appendingPathComponent("annotations.json")
        )
        let model = makeModel(annotationStore: annotationStore)

        model.readerNoteDraft = "   "
        model.addReaderNote()

        #expect(model.statusMessage == "Enter a note first")
        #expect(model.activeReaderAnnotations.isEmpty)
    }
}

private extension ReaderAnnotationTests {
    func makeModel(annotationStore: LocalAnnotationStore) -> AppModel {
        AppModel(
            store: InMemoryItemStore(),
            metadataRegistry: MetadataProviderRegistry(providers: [NoopMetadataProvider()]),
            citationFormatter: StubCitationFormatter(),
            storageConnectors: [],
            pdfDOIExtractor: NullPDFDOIExtractor(),
            attachmentStore: nil,
            annotationStore: annotationStore,
            collectionStore: makeCollectionStore(),
            noteStore: makeNoteStore(),
            relationshipStore: makeRelationshipStore(),
            readerProgressStore: makeReaderProgressStore()
        )
    }

    func makeCollectionStore() -> LocalCollectionStore? {
        try? LocalCollectionStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-reader-collections")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeNoteStore() -> LocalNoteStore? {
        try? LocalNoteStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-reader-notes")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeRelationshipStore() -> LocalRelationshipStore? {
        try? LocalRelationshipStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-reader-relationships")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    func makeReaderProgressStore() -> LocalReaderProgressStore? {
        try? LocalReaderProgressStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("citration-reader-progress")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
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
            .appendingPathComponent("citration-reader-annotation-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
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
}
