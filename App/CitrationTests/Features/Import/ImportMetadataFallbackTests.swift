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

        let model = makeAppModel(
            providers: [provider],
            attachmentStore: attachmentStore
        )
        await model.refreshItems()

        model.importer.importAttachments(urls: [sourceFile], mode: .createNewItemPerFile)
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
