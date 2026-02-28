import Testing
import Foundation
@testable import BCCommon

@Suite("Identifier")
struct IdentifierTests {
	@Test("round-trips through Codable")
	func codableRoundTrip() throws {
		let original = Identifier(type: .doi, value: "10.1038/nature12373")
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(Identifier.self, from: data)
		#expect(decoded == original)
	}

	@Test("IdentifierType has expected raw values")
	func rawValues() {
		#expect(IdentifierType.doi.rawValue == "doi")
		#expect(IdentifierType.isbn.rawValue == "isbn")
		#expect(IdentifierType.pmid.rawValue == "pmid")
		#expect(IdentifierType.arxiv.rawValue == "arxiv")
		#expect(IdentifierType.url.rawValue == "url")
	}

	@Test("all IdentifierType cases are present",
		  arguments: IdentifierType.allCases)
	func allCasesPresent(type: IdentifierType) {
		#expect(!type.rawValue.isEmpty)
	}
}
