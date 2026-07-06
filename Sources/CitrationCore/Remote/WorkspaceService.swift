import Foundation

// MARK: - WorkspaceServiceError

public enum WorkspaceServiceError: Error, LocalizedError, Sendable {
    case slugTaken
    case invalidSlug(String)
    case creationFailed(String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .slugTaken:
            "This workspace slug is already in use"
        case let .invalidSlug(reason):
            "Invalid slug: \(reason)"
        case let .creationFailed(details):
            "Workspace creation failed: \(details)"
        }
    }
}

// MARK: - WorkspaceService

public actor WorkspaceService {
    // MARK: Lifecycle

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: Public

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

    // MARK: Private

    private let apiClient: APIClient
}

// MARK: - CreateWorkspaceRequest

private struct CreateWorkspaceRequest: Encodable {
    let slug: String
    let displayName: String
}

// MARK: - WorkspacesResponse

private struct WorkspacesResponse: Decodable {
    let workspaces: [Workspace]
}

// MARK: - SlugAvailabilityResponse

private struct SlugAvailabilityResponse: Decodable {
    let available: Bool
    let slug: String?
}
