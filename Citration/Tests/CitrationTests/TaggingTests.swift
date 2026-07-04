import Testing
import Foundation
@testable import Citration
import CitrationCore

@Suite("Item Tagging")
@MainActor
struct TaggingTests {
	@Test("addTagToSelectedItem persists normalized tag")
	func addTagToSelectedItemPersistsNormalizedTag() async throws {
		let item = BCItem(title: "Tagged", tags: ["vision"])
		let model = makeModel(initialItems: [item])
		await model.refreshItems()
		model.selectItem(id: item.id)

		model.tagDraft = "  Machine   Learning  "
		model.addTagToSelectedItem()
		try await waitUntil { model.selectedItem?.tags == ["vision", "Machine Learning"] }

		#expect(model.tagDraft.isEmpty)
		#expect(model.statusMessage == "Added tag")
	}

	@Test("removeTag deletes tag from selected item")
	func removeTagDeletesTag() async throws {
		let item = BCItem(title: "Tagged", tags: ["vision", "machine learning"])
		let model = makeModel(initialItems: [item])
		await model.refreshItems()
		model.selectItem(id: item.id)

		let selected = try #require(model.selectedItem)
		model.removeTag("machine learning", from: selected)
		try await waitUntil { model.selectedItem?.tags == ["vision"] }

		#expect(model.statusMessage == "Removed tag")
	}

	@Test("metadata enrichment preserves existing tags")
	func metadataEnrichmentPreservesTags() async throws {
		let doi = "10.5555/tagged"
		let provider = TagMetadataProvider(
			records: [
				CanonicalMetadataRecord(
					title: "Resolved Title",
					creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
					publicationYear: 1843,
					itemType: .article,
					identifiers: [Identifier(type: .doi, value: doi)],
					confidence: 0.9,
					provenance: MetadataProvenance(providerName: "stub-provider")
				)
			],
			delayNanoseconds: 10_000_000
		)
		let item = BCItem(title: "Draft", tags: ["keep"])
		let tempDirectory = makeTempDirectory()
		defer { cleanupDirectory(tempDirectory) }
		let sourceFile = try makeFile(named: "tagged.pdf", contents: Data("dummy".utf8), in: tempDirectory)
		let attachmentStore = try LocalAttachmentStore(
			baseDirectory: tempDirectory.appendingPathComponent("attachments", isDirectory: true)
		)
		let model = makeModel(
			initialItems: [item],
			providers: [provider],
			pdfDOIExtractor: TagPDFDOIExtractor(doi: doi),
			attachmentStore: attachmentStore
		)
		await model.refreshItems()
		model.selectItem(id: item.id)

		model.importAttachments(urls: [sourceFile], mode: AppModel.AttachmentImportMode.attachToSelectedItem)
		try await waitUntil(timeout: 3.0) { model.selectedItem?.doi == doi }

		#expect(model.selectedItem?.tags == ["keep"])
	}
}

private struct TagMetadataProvider: MetadataProvider {
	let name: String = "tag-metadata"
	let records: [CanonicalMetadataRecord]
	let delayNanoseconds: UInt64

	func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord] {
		_ = request
		if delayNanoseconds > 0 {
			try? await Task.sleep(nanoseconds: delayNanoseconds)
		}
		return records
	}
}

private struct TagPDFDOIExtractor: PDFDOIExtracting {
	let doi: String?

	func extractDOI(from pdfURL: URL) async -> String? {
		_ = pdfURL
		return doi
	}
}

private extension TaggingTests {
	func makeModel(
		initialItems: [BCItem],
		providers: [any MetadataProvider] = [NoopMetadataProvider()],
		pdfDOIExtractor: any PDFDOIExtracting = NullPDFDOIExtractor(),
		attachmentStore: LocalAttachmentStore? = nil
	) -> AppModel {
		AppModel(
			store: InMemoryItemStore(initialItems: initialItems),
			metadataRegistry: MetadataProviderRegistry(providers: providers),
			citationFormatter: StubCitationFormatter(),
			storageConnectors: [],
			pdfDOIExtractor: pdfDOIExtractor,
			attachmentStore: attachmentStore,
			annotationStore: makeAnnotationStore(),
			collectionStore: makeCollectionStore(),
			noteStore: makeNoteStore(),
			relationshipStore: makeRelationshipStore()
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

	func makeAnnotationStore() -> LocalAnnotationStore? {
		try? LocalAnnotationStore(
			storeURL: FileManager.default.temporaryDirectory
				.appendingPathComponent("citration-tagging-annotations")
				.appendingPathComponent(UUID().uuidString)
				.appendingPathExtension("json")
		)
	}

	func makeCollectionStore() -> LocalCollectionStore? {
		try? LocalCollectionStore(
			storeURL: FileManager.default.temporaryDirectory
				.appendingPathComponent("citration-tagging-collections")
				.appendingPathComponent(UUID().uuidString)
				.appendingPathExtension("json")
		)
	}

	func makeNoteStore() -> LocalNoteStore? {
		try? LocalNoteStore(
			storeURL: FileManager.default.temporaryDirectory
				.appendingPathComponent("citration-tagging-notes")
				.appendingPathComponent(UUID().uuidString)
				.appendingPathExtension("json")
		)
	}

	func makeRelationshipStore() -> LocalRelationshipStore? {
		try? LocalRelationshipStore(
			storeURL: FileManager.default.temporaryDirectory
				.appendingPathComponent("citration-tagging-relationships")
				.appendingPathComponent(UUID().uuidString)
				.appendingPathExtension("json")
		)
	}

	func makeTempDirectory() -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("citration-tagging-tests", isDirectory: true)
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
}
