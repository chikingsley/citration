import Testing
import Foundation
@testable import BetterCiteApp
import BCCitationEngine
import BCDomain
import BCMetadataProviders
import BCStorage
import BCCommon

@Suite("BetterCiteApp")
@MainActor
struct BetterCiteAppTests {
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
}

// MARK: - Helpers

private extension BetterCiteAppTests {
	func makeModel(providers: [any MetadataProvider]) -> AppModel {
		AppModel(
			store: InMemoryItemStore(),
			metadataRegistry: MetadataProviderRegistry(providers: providers),
			citationFormatter: StubCitationFormatter(),
			storageConnectors: []
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
