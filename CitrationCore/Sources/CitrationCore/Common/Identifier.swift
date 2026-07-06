import Foundation

// MARK: - IdentifierType

public enum IdentifierType: String, Codable, CaseIterable, Sendable {
    case doi
    case isbn
    case pmid
    case arxiv
    case url
}

// MARK: - Identifier

public struct Identifier: Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(type: IdentifierType, value: String) {
        self.type = type
        self.value = value
    }

    // MARK: Public

    public var type: IdentifierType
    public var value: String
}
