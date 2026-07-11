import Foundation

// MARK: - ZoteroConnection

public struct ZoteroConnection: Hashable, Sendable {
    // MARK: Lifecycle

    public init(serverURL: URL, apiKey: String) throws {
        guard
            let components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || (scheme == "http" && Self.isLoopback(components.host)),
            components.host != nil
        else {
            throw ZoteroTransportError.invalidServerURL
        }
        let normalized = serverURL.absoluteString.hasSuffix("/")
            ? serverURL
            : URL(string: serverURL.absoluteString + "/") ?? serverURL
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ZoteroTransportError.missingAPIKey
        }
        self.serverURL = normalized
        self.apiKey = trimmedKey
    }

    // MARK: Public

    public let serverURL: URL
    public let apiKey: String

    // MARK: Private

    private static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

// MARK: - ZoteroKeyInfo

public struct ZoteroKeyInfo: Codable, Hashable, Sendable {
    public let access: JSONValue
    public let displayName: String
    public let key: String
    public let userID: Int64
    public let username: String

    public var canReadUserLibrary: Bool {
        access.objectValue?["user"]?.objectValue?["library"]?.boolValue == true
    }

    public var canWriteUserLibrary: Bool {
        access.objectValue?["user"]?.objectValue?["write"]?.boolValue == true
    }

    public var canAccessUserFiles: Bool {
        access.objectValue?["user"]?.objectValue?["files"]?.boolValue == true
    }
}

// MARK: - ZoteroTransportError

public enum ZoteroTransportError: Error, Equatable, Sendable {
    case invalidServerURL
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int)
    case missingHeader(String)
    case invalidHeader(String, value: String)
    case keyCannotReadLibrary
    case keyCannotWriteLibrary
    case keyCannotAccessFiles
    case preconditionFailed(remoteVersion: Int64?)
    case tooManyWriteObjects(Int)
}
