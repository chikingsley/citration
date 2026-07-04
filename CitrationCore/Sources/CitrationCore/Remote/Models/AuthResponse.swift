import Foundation

struct AuthResponse: Codable, Sendable {
	let accessToken: String
	let refreshToken: String
	let expiresAt: String
	let user: User
}
