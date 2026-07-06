import Foundation

// MARK: - AuthSession

public struct AuthSession: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    // MARK: Public

    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public func isExpired(referenceDate: Date = .now) -> Bool {
        referenceDate >= expiresAt
    }
}

// MARK: - AuthSessionStore

public protocol AuthSessionStore: Sendable {
    func loadSession() async -> AuthSession?
    func saveSession(_ session: AuthSession?) async
}

// MARK: - InMemoryAuthSessionStore

public actor InMemoryAuthSessionStore: AuthSessionStore {
    // MARK: Lifecycle

    public init(initialSession: AuthSession? = nil) {
        session = initialSession
    }

    // MARK: Public

    public func loadSession() -> AuthSession? {
        session
    }

    public func saveSession(_ session: AuthSession?) {
        self.session = session
    }

    // MARK: Private

    private var session: AuthSession?
}
