import Testing
import Foundation
@testable import BCDataRemote

@Suite("SaaSEnvironment")
struct SaaSEnvironmentTests {
    @Test("builds workspace host and URLs")
    func buildsWorkspaceURLs() throws {
        let environment = try SaaSEnvironment(rootDomain: "bettercite.app")
        let slug = try WorkspaceSlug("acme-lab")

        #expect(environment.workspaceHost(for: slug) == "acme-lab.bettercite.app")
        #expect(environment.workspaceAppURL(for: slug).absoluteString == "https://acme-lab.bettercite.app/")
        #expect(
            environment.workspaceAPIBaseURL(for: slug).absoluteString ==
            "https://api.bettercite.app/v1/workspaces/acme-lab"
        )
    }

    @Test("uses custom API base URL when provided")
    func usesCustomAPIBaseURL() throws {
        let customAPI = try #require(URL(string: "https://internal.example.test/api"))
        let environment = try SaaSEnvironment(rootDomain: "bettercite.app", apiBaseURL: customAPI)
        let slug = try WorkspaceSlug("team-42")

        #expect(environment.workspaceAPIBaseURL(for: slug).absoluteString == "https://internal.example.test/api/workspaces/team-42")
    }

    @Test("rejects invalid root domain")
    func rejectsInvalidRootDomain() {
        #expect(throws: SaaSEnvironmentError.invalidRootDomain) {
            _ = try SaaSEnvironment(rootDomain: "bad/domain")
        }
    }
}
