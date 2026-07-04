import Foundation

public enum WorkspaceSlugError: Error, Equatable, Sendable {
    case empty
    case invalidLength(Int)
    case invalidCharacters
    case startsOrEndsWithHyphen
    case reserved(String)
}

public struct WorkspaceSlug: Codable, Hashable, Sendable, CustomStringConvertible {
    public static let defaultReservedWords: Set<String> = [
        "www", "api", "admin", "status", "support", "help", "app", "root"
    ]

    public let value: String

    public var description: String {
        value
    }

    public init(_ rawValue: String, reservedWords: Set<String> = WorkspaceSlug.defaultReservedWords) throws {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            throw WorkspaceSlugError.empty
        }

        guard (3...63).contains(normalized.count) else {
            throw WorkspaceSlugError.invalidLength(normalized.count)
        }

        guard normalized.first != "-", normalized.last != "-" else {
            throw WorkspaceSlugError.startsOrEndsWithHyphen
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let hasOnlyAllowedCharacters = normalized.unicodeScalars.allSatisfy { scalar in
            allowedCharacters.contains(scalar)
        }
        guard hasOnlyAllowedCharacters else {
            throw WorkspaceSlugError.invalidCharacters
        }

        guard !reservedWords.contains(normalized) else {
            throw WorkspaceSlugError.reserved(normalized)
        }

        self.value = normalized
    }
}
