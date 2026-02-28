import Testing
@testable import BCCommon

@Suite("Creator")
struct CreatorTests {
	@Test("displayName returns literalName when present")
	func displayNameFallsBackToLiteral() {
		let creator = Creator(literalName: "Ada Lovelace")
		#expect(creator.displayName == "Ada Lovelace")
	}

	@Test("displayName joins givenName and familyName")
	func displayNameUsesGivenAndFamily() {
		let creator = Creator(givenName: "Ada", familyName: "Lovelace")
		#expect(creator.displayName == "Ada Lovelace")
	}

	@Test("displayName falls back to Unknown when all names missing")
	func displayNameFallsBackToUnknown() {
		let creator = Creator()
		#expect(creator.displayName == "Unknown")
	}

	@Test("displayName ignores empty strings")
	func displayNameIgnoresEmptyStrings() {
		let creator = Creator(givenName: "", familyName: "", literalName: "")
		#expect(creator.displayName == "Unknown")
	}

	@Test("displayName with only familyName")
	func displayNameWithOnlyFamily() {
		let creator = Creator(familyName: "Lovelace")
		#expect(creator.displayName == "Lovelace")
	}
}
