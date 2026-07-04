import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public func isExpired(referenceDate: Date = .now) -> Bool {
        referenceDate >= expiresAt
    }
}

public protocol AuthSessionStore: Sendable {
    func loadSession() async -> AuthSession?
    func saveSession(_ session: AuthSession?) async
}

public actor InMemoryAuthSessionStore: AuthSessionStore {
    private var session: AuthSession?

    public init(initialSession: AuthSession? = nil) {
        self.session = initialSession
    }

    public func loadSession() async -> AuthSession? {
        session
    }

    public func saveSession(_ session: AuthSession?) async {
        self.session = session
    }
}
