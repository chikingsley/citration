import Foundation

public enum SaaSEnvironmentError: Error, Equatable, Sendable {
    case invalidRootDomain
}

public struct SaaSEnvironment: Codable, Equatable, Sendable {
    public let rootDomain: String
    public let apiBaseURL: URL

    public init(rootDomain: String, apiBaseURL: URL? = nil) throws {
        let normalizedDomain = rootDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard Self.isValidRootDomain(normalizedDomain) else {
            throw SaaSEnvironmentError.invalidRootDomain
        }

        self.rootDomain = normalizedDomain

        if let apiBaseURL {
            guard apiBaseURL.scheme != nil, apiBaseURL.host != nil else {
                throw SaaSEnvironmentError.invalidRootDomain
            }
            self.apiBaseURL = apiBaseURL
        } else if let defaultAPI = URL(string: "https://api.\(normalizedDomain)/v1") {
            self.apiBaseURL = defaultAPI
        } else {
            throw SaaSEnvironmentError.invalidRootDomain
        }
    }

    public func workspaceHost(for slug: WorkspaceSlug) -> String {
        "\(slug.value).\(rootDomain)"
    }

    public func workspaceAppURL(for slug: WorkspaceSlug, scheme: String = "https") -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = workspaceHost(for: slug)
        components.path = "/"
        guard let url = components.url else {
            preconditionFailure("Failed to create workspace app URL for slug \(slug.value)")
        }
        return url
    }

    public func workspaceAPIBaseURL(for slug: WorkspaceSlug) -> URL {
        apiBaseURL
            .appending(path: "workspaces")
            .appending(path: slug.value)
    }

    private static func isValidRootDomain(_ value: String) -> Bool {
        guard value.count >= 3,
              value.contains("."),
              !value.hasPrefix("."),
              !value.hasSuffix("."),
              !value.contains("/"),
              !value.contains(" ") else {
            return false
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        return value.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
}
