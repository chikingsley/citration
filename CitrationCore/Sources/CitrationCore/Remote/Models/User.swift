import Foundation

public struct User: Codable, Identifiable, Equatable, Sendable {
	public let id: String
	public let email: String?
	public let displayName: String?
	public let createdAt: String?

	public init(id: String, email: String? = nil, displayName: String? = nil, createdAt: String? = nil) {
		self.id = id
		self.email = email
		self.displayName = displayName
		self.createdAt = createdAt
	}
}
