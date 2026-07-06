import Foundation

// MARK: - AuthServiceError

public enum AuthServiceError: Error, LocalizedError, Sendable {
    case invalidIdentityToken
    case signInFailed(String)
    case signOutFailed(String)
    case sessionExpired

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .invalidIdentityToken:
            "Invalid Apple identity token"
        case let .signInFailed(details):
            "Sign in failed: \(details)"
        case let .signOutFailed(details):
            "Sign out failed: \(details)"
        case .sessionExpired:
            "Session has expired"
        }
    }
}

// MARK: - AuthService

public actor AuthService {
    // MARK: Lifecycle

    public init(apiClient: APIClient, sessionStore: AuthSessionStore, environment: SaaSEnvironment) {
        self.apiClient = apiClient
        self.sessionStore = sessionStore
        self.environment = environment
    }

    // MARK: Public

    public func signInWithApple(identityToken: String) async throws -> AuthSession {
        guard !identityToken.isEmpty else {
            throw AuthServiceError.invalidIdentityToken
        }

        let body = AppleSignInRequest(identityToken: identityToken)
        let response: AuthResponse = try await apiClient.post(path: "auth/apple", body: body)

        let session = AuthSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: ISO8601DateFormatter().date(from: response.expiresAt) ?? Date()
        )
        await sessionStore.saveSession(session)
        return session
    }

    public func refreshSession() async throws -> AuthSession {
        guard let session = await sessionStore.loadSession() else {
            throw AuthServiceError.sessionExpired
        }

        let body = RefreshTokenRequest(refreshToken: session.refreshToken)
        let response: AuthResponse = try await apiClient.post(path: "auth/refresh", body: body)

        let newSession = AuthSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: ISO8601DateFormatter().date(from: response.expiresAt) ?? Date()
        )
        await sessionStore.saveSession(newSession)
        return newSession
    }

    public func signOut() async throws {
        if let session = await sessionStore.loadSession() {
            let body = RevokeRequest(refreshToken: session.refreshToken)
            let _: SuccessResponse = try await apiClient.post(path: "auth/revoke", body: body)
        }
        await sessionStore.saveSession(nil)
    }

    public func currentUser() async throws -> User {
        try await apiClient.get(path: "auth/me")
    }

    public func hasValidSession() async -> Bool {
        guard let session = await sessionStore.loadSession() else {
            return false
        }
        return !session.isExpired()
    }

    // MARK: Private

    private let apiClient: APIClient
    private let sessionStore: AuthSessionStore
    private let environment: SaaSEnvironment
}

// MARK: - AppleSignInRequest

private struct AppleSignInRequest: Encodable {
    let identityToken: String
}

// MARK: - RefreshTokenRequest

private struct RefreshTokenRequest: Encodable {
    let refreshToken: String
}

// MARK: - RevokeRequest

private struct RevokeRequest: Encodable {
    let refreshToken: String
}

// MARK: - SuccessResponse

private struct SuccessResponse: Decodable {
    let success: Bool
}
