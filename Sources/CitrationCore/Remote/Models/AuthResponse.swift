import Foundation

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: String
    let user: User
}
