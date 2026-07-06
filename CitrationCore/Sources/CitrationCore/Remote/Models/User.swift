import Foundation

public struct User: Codable, Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(id: String, email: String? = nil, displayName: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
    }

    // MARK: Public

    public let id: String
    public let email: String?
    public let displayName: String?
    public let createdAt: String?
}
