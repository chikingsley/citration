import Testing
import Foundation
@testable import BetterCiteMac
import BCCitationEngine
import BCDomain
import BCMetadataProviders
import BCStorage
import BCCommon

@Suite("BetterCiteMac")
@MainActor
struct BetterCiteMacTests {
	@Test("MockDOIProvider returns record for known DOI")
	func mockDOIProviderReturnsRecordForDOI() async throws {
		let provider = MockDOIMetadataProvider()
		let request = MetadataResolutionRequest(
			identifiers: [Identifier(type: .doi, value: "10.1038/nature12373")]
		)
		let records = try await provider.resolve(request)
		#expect(records.count == 1)
		#expect(records.first?.title == "Nanometre-scale thermometry in a living cell")
	}

	@Test("addByDOI success updates state and status lifecycle")
	func addByDOISuccessUpdatesStateAndStatusLifecycle() async throws {
		let doi = "10.1038/nature12373"
		let provider = StubMetadataProvider(
			records: [
				CanonicalMetadataRecord(
					title: "A Great Paper",
					creators: [Creator(givenName: "Ada", familyName: "Lovelace")],
					publicationYear: 1843,
					itemType: .article,
					identifiers: [Identifier(type: .doi, value: doi)],
					confidence: 0.95,
					provenance: MetadataProvenance(providerName: "stub-provider")
				)
			],
			delayNanoseconds: 50_000_000
		)
		let model = makeModel(providers: [provider])
		await model.refreshItems()

		model.doiInput = doi
		model.addByDOI()

		#expect(model.isResolvingDOI)
		#expect(model.statusMessage == "Resolving DOI \(doi)...")

		try await waitUntil { !model.isResolvingDOI }

		#expect(model.statusMessage == "Added: A Great Paper")
		#expect(model.doiInput.isEmpty)
		#expect(model.items.count == 1)
		#expect(model.items.first?.doi == doi)
		#expect(model.selectedItemID != nil)
		#expect(model.citationPreview.contains("[apa]"))
	}

	@Test("addByDOI no match sets failure status and stops resolving")
	func addByDOINoMatchSetsFailureStatusAndStopsResolving() async throws {
		let doi = "10.1000/unknown"
		let provider = StubMetadataProvider(records: [], delayNanoseconds: 50_000_000)
		let model = makeModel(providers: [provider])
		await model.refreshItems()

		model.doiInput = doi
		model.addByDOI()

		#expect(model.isResolvingDOI)
		#expect(model.statusMessage == "Resolving DOI \(doi)...")

		try await waitUntil { !model.isResolvingDOI }

		#expect(model.statusMessage == "No metadata found for \(doi)")
		#expect(model.items.isEmpty)
		#expect(model.doiInput == doi)
	}

	@Test("addByDOI rejects empty input immediately")
	func addByDOIRejectsEmptyInputImmediately() async {
		let model = makeModel(providers: [NoopMetadataProvider()])
		model.doiInput = "   "
		model.addByDOI()

		#expect(!model.isResolvingDOI)
		#expect(model.statusMessage == "Enter a DOI first")
	}

	@Test("addByDOI normalizes DOI input and metadata whitespace")
	func addByDOINormalizesDOIInputAndMetadataWhitespace() async throws {
		let provider = StubMetadataProvider(
			records: [
				CanonicalMetadataRecord(
					title: "  A   Great   Paper  ",
					creators: [Creator(givenName: "  Ada  ", familyName: "  Lovelace ")],
					publicationYear: 1843,
					itemType: .article,
					identifiers: [Identifier(type: .doi, value: "10.1038/NATURE12373")],
					confidence: 0.95,
					provenance: MetadataProvenance(providerName: "stub-provider")
				)
			],
			delayNanoseconds: 20_000_000
		)
		let model = makeModel(providers: [provider])
		await model.refreshItems()

		model.doiInput = "  DOI: 10.1038/NATURE12373  "
		model.addByDOI()
		try await waitUntil { !model.isResolvingDOI }

		#expect(model.items.count == 1)
		#expect(model.items.first?.doi == "10.1038/nature12373")
		#expect(model.items.first?.title == "A Great Paper")
		#expect(model.items.first?.creators.first?.displayName == "Ada Lovelace")
	}

	@Test("import enriches item with normalized DOI title and creators")
	func importEnrichesItemWithNormalizedDOITitleAndCreators() async throws {
		let doi = "10.5555/abc123"
		let provider = StubMetadataProvider(
			records: [
				CanonicalMetadataRecord(
					title: "  Real   Metadata   Title ",
					creators: [
						Creator(givenName: "  Grace ", familyName: " Hopper "),
						Creator(givenName: "  Alan", familyName: "  Turing  ")
					],
					publicationYear: 1952,
					itemType: .article,
					identifiers: [Identifier(type: .doi, value: doi)],
					confidence: 0.9,
					provenance: MetadataProvenance(providerName: "stub-provider")
				)
			],
			delayNanoseconds: 10_000_000
		)

		let tempDirectory = makeTempDirectory()
		defer { cleanupDirectory(tempDirectory) }
		let sourceFile = try makeFile(named: "input.pdf", contents: Data("dummy".utf8), in: tempDirectory)
		let attachmentsDirectory = tempDirectory.appendingPathComponent("attachments", isDirectory: true)
		let attachmentStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)

		let model = makeModel(
			providers: [provider],
			pdfDOIExtractor: StubPDFDOIExtractor(doi: doi),
			attachmentStore: attachmentStore
		)
		await model.refreshItems()

		model.importAttachments(urls: [sourceFile], mode: .createNewItemPerFile)
		try await waitUntil(timeout: 3.0) { model.items.count == 1 && model.items.first?.doi == doi }

		let imported = try #require(model.items.first)
		#expect(imported.title == "Real Metadata Title")
		#expect(imported.creators.first?.displayName == "Grace Hopper")
		#expect(imported.creators.count == 2)
		#expect(model.statusMessage.contains("detected 1 DOI"))
	}

	@Test("import resolves metadata in arXiv then DOI order")
	func importResolvesMetadataInArXivThenDOIOrder() async throws {
		let recorder = MetadataRequestRecorder()
		let provider = OrderedResolutionProvider(recorder: recorder)

		let tempDirectory = makeTempDirectory()
		defer { cleanupDirectory(tempDirectory) }
		let sourceFile = try makeFile(named: "order.pdf", contents: Data("dummy".utf8), in: tempDirectory)
		let attachmentsDirectory = tempDirectory.appendingPathComponent("attachments", isDirectory: true)
		let attachmentStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)

		let extractor = StubPDFCandidateExtractor(
			candidates: PDFMetadataCandidates(
				identifiers: [
					Identifier(type: .arxiv, value: "2401.01234"),
					Identifier(type: .doi, value: "10.5555/fallback-doi"),
					Identifier(type: .isbn, value: "9780306406157")
				],
				titleHints: ["Some Fallback Title"]
			)
		)

		let model = makeModel(
			providers: [provider],
			pdfDOIExtractor: extractor,
			attachmentStore: attachmentStore
		)
		await model.refreshItems()

		model.importAttachments(urls: [sourceFile], mode: .createNewItemPerFile)
		try await waitUntil(timeout: 3.0) { model.items.first?.title == "Resolved From DOI" }

		let requests = await recorder.requests()
		#expect(requests.count == 2)
		#expect(requests[0].identifiers.first?.type == .arxiv)
		#expect(requests[1].identifiers.first?.type == .doi)
		#expect(model.items.first?.doi == "10.5555/fallback-doi")
	}

	@Test("import does not leave orphan item when file copy fails")
	func importFailureDoesNotPersistOrphanItem() async throws {
		let tempDirectory = makeTempDirectory()
		defer { cleanupDirectory(tempDirectory) }
		let missingFile = tempDirectory.appendingPathComponent("missing.pdf")
		let attachmentsDirectory = tempDirectory.appendingPathComponent("attachments", isDirectory: true)
		let attachmentStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)

		let model = makeModel(
			providers: [MockDOIMetadataProvider()],
			pdfDOIExtractor: NullPDFDOIExtractor(),
			attachmentStore: attachmentStore
		)
		await model.refreshItems()

		model.importAttachments(urls: [missingFile], mode: .createNewItemPerFile)
		try await waitUntil(timeout: 3.0) { !model.isImportingAttachments }

		#expect(model.items.isEmpty)
		#expect(model.statusMessage == "Import failed")
	}

	@Test("import surfaces new item before slow PDF enrichment completes")
	func importShowsItemBeforeSlowEnrichmentFinishes() async throws {
		let tempDirectory = makeTempDirectory()
		defer { cleanupDirectory(tempDirectory) }
		let sourceFile = try makeFile(named: "slow.pdf", contents: Data("dummy".utf8), in: tempDirectory)
		let attachmentsDirectory = tempDirectory.appendingPathComponent("attachments", isDirectory: true)
		let attachmentStore = try LocalAttachmentStore(baseDirectory: attachmentsDirectory)

		let slowExtractor = SlowPDFExtractor(delayNanoseconds: 2_000_000_000)
		let model = makeModel(
			providers: [MockDOIMetadataProvider()],
			pdfDOIExtractor: slowExtractor,
			attachmentStore: attachmentStore
		)
		await model.refreshItems()

		model.importAttachments(urls: [sourceFile], mode: .createNewItemPerFile)

		try await waitUntil(timeout: 0.8) { model.items.count == 1 }
		#expect(model.items.first?.title == "slow")

		try await waitUntil(timeout: 4.0) { !model.isImportingAttachments }
	}
}

// MARK: - Helpers

private extension BetterCiteMacTests {
	func makeModel(providers: [any MetadataProvider]) -> AppModel {
		makeModel(
			providers: providers,
			pdfDOIExtractor: NullPDFDOIExtractor(),
			attachmentStore: nil
		)
	}

	func makeModel(
		providers: [any MetadataProvider],
		pdfDOIExtractor: any PDFDOIExtracting,
		attachmentStore: LocalAttachmentStore?
	) -> AppModel {
		AppModel(
			store: InMemoryItemStore(),
			metadataRegistry: MetadataProviderRegistry(providers: providers),
			citationFormatter: StubCitationFormatter(),
			storageConnectors: [],
			pdfDOIExtractor: pdfDOIExtractor,
			attachmentStore: attachmentStore
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
			.appendingPathComponent("better-cite-appmodel-tests", isDirectory: true)
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

private struct StubMetadataProvider: MetadataProvider {
	let name: String = "stub-metadata"
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

private struct StubPDFDOIExtractor: PDFDOIExtracting {
	let doi: String?

	func extractDOI(from pdfURL: URL) async -> String? {
		_ = pdfURL
		return doi
	}
}

private struct StubPDFCandidateExtractor: PDFDOIExtracting {
	let candidates: PDFMetadataCandidates

	func extractDOI(from pdfURL: URL) async -> String? {
		_ = pdfURL
		return candidates.detectedDOI
	}

	func extractCandidates(from pdfURL: URL) async -> PDFMetadataCandidates {
		_ = pdfURL
		return candidates
	}
}

private struct SlowPDFExtractor: PDFDOIExtracting {
	let delayNanoseconds: UInt64

	func extractDOI(from pdfURL: URL) async -> String? {
		_ = pdfURL
		if delayNanoseconds > 0 {
			try? await Task.sleep(nanoseconds: delayNanoseconds)
		}
		return nil
	}
}

private actor MetadataRequestRecorder {
	private var storedRequests: [MetadataResolutionRequest] = []

	func append(_ request: MetadataResolutionRequest) {
		storedRequests.append(request)
	}

	func requests() -> [MetadataResolutionRequest] {
		storedRequests
	}
}

private struct OrderedResolutionProvider: MetadataProvider {
	let name: String = "ordered-resolution"
	let recorder: MetadataRequestRecorder

	func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord] {
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
