import Foundation
import BCMetadataProviders
import BCCommon

struct MockDOIMetadataProvider: MetadataProvider {
	let name: String = "mock-doi"

	func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord] {
		guard let doi = request.identifiers.first(where: { $0.type == .doi })?.value else {
			return []
		}

		let normalized = doi.lowercased()
		let metadata: (title: String, year: Int, creator: Creator)

		switch normalized {
		case "10.1038/nature12373":
			metadata = (
				title: "Nanometre-scale thermometry in a living cell",
				year: 2013,
				creator: Creator(givenName: "Guanxiong", familyName: "Kucsko")
			)
		case "10.1126/science.169.3946.635":
			metadata = (
				title: "The Structure of Scientific Revolutions",
				year: 1970,
				creator: Creator(givenName: "Thomas", familyName: "Kuhn")
			)
		default:
			metadata = (
				title: "Imported DOI \(doi)",
				year: 2026,
				creator: Creator(literalName: "Unknown")
			)
		}

		let record = CanonicalMetadataRecord(
			title: metadata.title,
			creators: [metadata.creator],
			publicationYear: metadata.year,
			itemType: .article,
			identifiers: [Identifier(type: .doi, value: doi)],
			confidence: 0.95,
			provenance: MetadataProvenance(providerName: name, sourceRecordID: doi)
		)

		return [record]
	}
}
