import Foundation

public enum WorkspaceServiceError: Error, LocalizedError, Sendable {
	case slugTaken
	case invalidSlug(String)
	case creationFailed(String)

	public var errorDescription: String? {
		switch self {
		case .slugTaken:
			return "This workspace slug is already in use"
		case .invalidSlug(let reason):
			return "Invalid slug: \(reason)"
		case .creationFailed(let details):
			return "Workspace creation failed: \(details)"
		}
	}
}

public actor WorkspaceService {
	private let apiClient: APIClient

	public init(apiClient: APIClient) {
		self.apiClient = apiClient
	}

	public func createWorkspace(slug: String, displayName: String) async throws -> Workspace {
		let body = CreateWorkspaceRequest(slug: slug, displayName: displayName)
		return try await apiClient.post(path: "workspaces", body: body)
	}

	public func listWorkspaces() async throws -> [Workspace] {
		let response: WorkspacesResponse = try await apiClient.get(path: "workspaces")
		return response.workspaces
	}

	public func checkSlugAvailability(_ slug: String) async throws -> Bool {
		let response: SlugAvailabilityResponse = try await apiClient.get(
			path: "workspaces/\(slug)/availability"
		)
		return response.available
	}
}

private struct CreateWorkspaceRequest: Encodable, Sendable {
	let slug: String
	let displayName: String
}

private struct WorkspacesResponse: Decodable, Sendable {
	let workspaces: [Workspace]
}

private struct SlugAvailabilityResponse: Decodable, Sendable {
	let available: Bool
	let slug: String?
}
