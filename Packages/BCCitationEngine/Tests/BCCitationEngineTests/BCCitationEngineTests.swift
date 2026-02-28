import Testing
import Foundation
@testable import BCCitationEngine

@Suite("StubCitationFormatter")
struct BCCitationEngineTests {
	@Test("renders cluster with style prefix")
	func stubFormatterRendersClusterWithStylePrefix() async throws {
		let formatter = StubCitationFormatter()
		let style = CitationStyle(id: "apa", title: "APA")
		let cluster = CitationCluster(items: [CitationItem(itemID: UUID())])

		let output = try await formatter.formatCluster(
			cluster,
			style: style,
			options: CitationRenderOptions(format: .plainText)
		)

		#expect(output.text.hasPrefix("[apa] "))
	}

	@Test("renders bibliography with correct entry count")
	func stubFormatterRendersBibliographyEntryCount() async throws {
		let formatter = StubCitationFormatter()
		let style = CitationStyle(id: "chicago-author-date", title: "Chicago Author-Date")
		let ids = [UUID(), UUID(), UUID()]

		let bibliography = try await formatter.formatBibliography(
			itemIDs: ids,
			style: style,
			options: CitationRenderOptions(format: .markdown)
		)

		#expect(bibliography.entries.count == 3)
		#expect(bibliography.format == .markdown)
	}

	@Test("throws for empty cluster")
	func stubFormatterThrowsForEmptyCluster() async throws {
		let formatter = StubCitationFormatter()
		let style = CitationStyle(id: "apa", title: "APA")
		let cluster = CitationCluster(items: [])

		await #expect(throws: CitationEngineError.self) {
			try await formatter.formatCluster(
				cluster,
				style: style,
				options: CitationRenderOptions(format: .plainText)
			)
		}
	}

	@Test("includes locator, prefix, suffix, and suppress-author in output")
	func stubFormatterIncludesAllFields() async throws {
		let formatter = StubCitationFormatter()
		let style = CitationStyle(id: "apa", title: "APA")
		let itemID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
		let cluster = CitationCluster(
			items: [
				CitationItem(
					itemID: itemID,
					locator: "p. 12",
					prefix: "see",
					suffix: "for details",
					suppressAuthor: true
				)
			]
		)

		let output = try await formatter.formatCluster(
			cluster,
			style: style,
			options: CitationRenderOptions(format: .plainText)
		)

		#expect(output.text.contains("loc=p. 12"))
		#expect(output.text.contains("prefix=see"))
		#expect(output.text.contains("suffix=for details"))
		#expect(output.text.contains("suppress-author"))
	}

	@Test("empty bibliography returns no entries")
	func emptyBibliography() async throws {
		let formatter = StubCitationFormatter()
		let style = CitationStyle(id: "apa", title: "APA")

		let bibliography = try await formatter.formatBibliography(
			itemIDs: [],
			style: style,
			options: CitationRenderOptions(format: .plainText)
		)

		#expect(bibliography.entries.isEmpty)
	}
}
