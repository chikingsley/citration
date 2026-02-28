import Foundation

public enum IdentifierType: String, Codable, CaseIterable, Sendable {
	case doi
	case isbn
	case pmid
	case arxiv
	case url
}

public struct Identifier: Hashable, Codable, Sendable {
	public var type: IdentifierType
	public var value: String

	public init(type: IdentifierType, value: String) {
		self.type = type
		self.value = value
	}
}
