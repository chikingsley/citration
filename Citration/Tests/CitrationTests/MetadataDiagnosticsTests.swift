import Testing
import Foundation
@testable import Citration
import CitrationCore

@Suite("Metadata diagnostics")
@MainActor
struct MetadataDiagnosticsTests {
	@Test("addByDOI preserves metadata conflict diagnostics")
	func addByDOIPreservesMetadataConflictDiagnostics() async throws {
		let doi = "10.1000/disagree"
		let provider = ConflictingMetadataProvider(doi: doi)
		let model = makeModel(providers: [provider])
		await model.refreshItems()

		model.doiInput = doi
		model.addByDOI()
		try await waitUntil { !model.isResolvingDOI }

		#expect(model.statusMessage == "Added: Published Title · check metadata")
		#expect(model.items.first?.title == "Published Title")
		#expect(Set(model.metadataConflicts.map(\.field)) == [.title, .publicationYear, .itemType])
		#expect(model.metadataWarnings.isEmpty)
	}
}

private extension MetadataDiagnosticsTests {
	func makeModel(providers: [any MetadataProvider]) -> AppModel {
		AppModel(
			store: InMemoryItemStore(),
			metadataRegistry: MetadataProviderRegistry(providers: providers),
			citationFormatter: StubCitationFormatter(),
			storageConnectors: [],
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

	func makeAnnotationStore() -> LocalAnnotationStore? {
		try? LocalAnnotationStore(
			storeURL: temporaryStoreURL(named: "metadata-diagnostics-annotations")
		)
	}

	func makeCollectionStore() -> LocalCollectionStore? {
		try? LocalCollectionStore(
			storeURL: temporaryStoreURL(named: "metadata-diagnostics-collections")
		)
	}

	func makeNoteStore() -> LocalNoteStore? {
		try? LocalNoteStore(
			storeURL: temporaryStoreURL(named: "metadata-diagnostics-notes")
		)
	}

	func makeRelationshipStore() -> LocalRelationshipStore? {
		try? LocalRelationshipStore(
			storeURL: temporaryStoreURL(named: "metadata-diagnostics-relationships")
		)
	}

	func makeReaderProgressStore() -> LocalReaderProgressStore? {
		try? LocalReaderProgressStore(
			storeURL: temporaryStoreURL(named: "metadata-diagnostics-reader-progress")
		)
	}

	func temporaryStoreURL(named name: String) -> URL {
		FileManager.default.temporaryDirectory
			.appendingPathComponent(name)
			.appendingPathComponent(UUID().uuidString)
			.appendingPathExtension("json")
	}
}

private struct ConflictingMetadataProvider: MetadataProvider {
	let name = "conflicting-metadata"
	let doi: String

	func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord] {
		_ = request
		return [
			CanonicalMetadataRecord(
				title: "Draft Title",
				publicationYear: 2023,
				itemType: .preprint,
				identifiers: [Identifier(type: .doi, value: doi)],
				confidence: 0.60,
				provenance: MetadataProvenance(providerName: "OpenAlex")
			),
			CanonicalMetadataRecord(
				title: "Published Title",
				publicationYear: 2024,
				itemType: .article,
				identifiers: [Identifier(type: .doi, value: doi)],
				confidence: 0.95,
				provenance: MetadataProvenance(providerName: "Crossref")
			)
		]
	}
}
