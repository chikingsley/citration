import Foundation

public struct Creator: Identifiable, Hashable, Codable, Sendable {
	public var id: UUID
	public var givenName: String?
	public var familyName: String?
	public var literalName: String?

	public init(
		id: UUID = UUID(),
		givenName: String? = nil,
		familyName: String? = nil,
		literalName: String? = nil
	) {
		self.id = id
		self.givenName = givenName
		self.familyName = familyName
		self.literalName = literalName
	}

	public var displayName: String {
		if let literalName, !literalName.isEmpty {
			return literalName
		}

		let pieces: [String] = [givenName, familyName].compactMap { value in
			guard let value, !value.isEmpty else { return nil }
			return value
		}

		if pieces.isEmpty {
			return "Unknown"
		}

		return pieces.joined(separator: " ")
	}
}
