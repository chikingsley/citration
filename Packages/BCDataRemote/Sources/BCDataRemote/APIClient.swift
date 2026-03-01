import Foundation

public enum APIClientError: Error, LocalizedError, Sendable {
	case invalidURL(String)
	case unauthorized
	case httpError(statusCode: Int, body: String)
	case decodingError(String)
	case networkError(String)

	public var errorDescription: String? {
		switch self {
		case .invalidURL(let url):
			return "Invalid URL: \(url)"
		case .unauthorized:
			return "Authentication required"
		case .httpError(let statusCode, let body):
			return "HTTP \(statusCode): \(body)"
		case .decodingError(let details):
			return "Failed to decode response: \(details)"
		case .networkError(let details):
			return "Network error: \(details)"
		}
	}
}

public actor APIClient {
	private let environment: SaaSEnvironment
	private let sessionStore: AuthSessionStore
	private let urlSession: URLSession
	private let decoder: JSONDecoder
	private let encoder: JSONEncoder

	public init(
		environment: SaaSEnvironment,
		sessionStore: AuthSessionStore,
		urlSession: URLSession = .shared
	) {
		self.environment = environment
		self.sessionStore = sessionStore
		self.urlSession = urlSession

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		self.decoder = decoder

		let encoder = JSONEncoder()
		encoder.keyEncodingStrategy = .convertToSnakeCase
		self.encoder = encoder
	}

	public func get<T: Decodable & Sendable>(path: String) async throws -> T {
		try await request(method: "GET", path: path)
	}

	public func post<T: Decodable & Sendable, B: Encodable & Sendable>(path: String, body: B) async throws -> T {
		try await request(method: "POST", path: path, body: body)
	}

	public func post<T: Decodable & Sendable>(path: String) async throws -> T {
		try await request(method: "POST", path: path)
	}

	public func delete(path: String) async throws {
		let _: EmptyResponse = try await request(method: "DELETE", path: path)
	}

	private func request<T: Decodable & Sendable>(
		method: String,
		path: String,
		body: (any Encodable & Sendable)? = nil,
		attemptRefresh: Bool = true
	) async throws -> T {
		let url = environment.apiBaseURL.appendingPathComponent(path)
		var urlRequest = URLRequest(url: url)
		urlRequest.httpMethod = method
		urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

		// Attach auth header if session exists
		if let session = await sessionStore.loadSession() {
			urlRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
		}

		if let body {
			urlRequest.httpBody = try encoder.encode(body)
		}

		let (data, response) = try await urlSession.data(for: urlRequest)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw APIClientError.networkError("Invalid response type")
		}

		// Handle 401 with automatic refresh
		if httpResponse.statusCode == 401 && attemptRefresh {
			if let session = await sessionStore.loadSession() {
				let refreshed = try await refreshToken(session.refreshToken)
				await sessionStore.saveSession(refreshed)
				return try await request(method: method, path: path, body: body, attemptRefresh: false)
			}
			throw APIClientError.unauthorized
		}

		guard (200...299).contains(httpResponse.statusCode) else {
			let body = String(data: data, encoding: .utf8) ?? ""
			throw APIClientError.httpError(statusCode: httpResponse.statusCode, body: body)
		}

		do {
			return try decoder.decode(T.self, from: data)
		} catch {
			throw APIClientError.decodingError(error.localizedDescription)
		}
	}

	private func refreshToken(_ refreshToken: String) async throws -> AuthSession {
		let url = environment.apiBaseURL.appendingPathComponent("auth/refresh")
		var urlRequest = URLRequest(url: url)
		urlRequest.httpMethod = "POST"
		urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let body = RefreshRequest(refreshToken: refreshToken)
		urlRequest.httpBody = try encoder.encode(body)

		let (data, response) = try await urlSession.data(for: urlRequest)

		guard let httpResponse = response as? HTTPURLResponse,
			  (200...299).contains(httpResponse.statusCode) else {
			throw APIClientError.unauthorized
		}

		let authResponse = try decoder.decode(AuthResponse.self, from: data)
		return AuthSession(
			accessToken: authResponse.accessToken,
			refreshToken: authResponse.refreshToken,
			expiresAt: ISO8601DateFormatter().date(from: authResponse.expiresAt) ?? Date()
		)
	}
}

private struct RefreshRequest: Encodable, Sendable {
	let refreshToken: String
}

private struct EmptyResponse: Decodable, Sendable {}
