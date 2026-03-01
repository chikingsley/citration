import Foundation

public struct Workspace: Codable, Identifiable, Equatable, Sendable {
	public let id: String
	public let slug: String
	public let displayName: String
	public let role: String?
	public let createdAt: String

	public init(id: String, slug: String, displayName: String, role: String? = nil, createdAt: String) {
		self.id = id
		self.slug = slug
		self.displayName = displayName
		self.role = role
		self.createdAt = createdAt
	}
}
