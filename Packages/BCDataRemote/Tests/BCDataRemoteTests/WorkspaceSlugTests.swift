import Testing
@testable import BCDataRemote

@Suite("WorkspaceSlug")
struct WorkspaceSlugTests {
    @Test("normalizes uppercase and trims whitespace")
    func normalizesInput() throws {
        let slug = try WorkspaceSlug("  My-Lab  ")
        #expect(slug.value == "my-lab")
    }

    @Test("rejects empty slug")
    func rejectsEmpty() {
        #expect(throws: WorkspaceSlugError.empty) {
            _ = try WorkspaceSlug("   ")
        }
    }

    @Test("rejects invalid length")
    func rejectsInvalidLength() {
        #expect(throws: WorkspaceSlugError.invalidLength(2)) {
            _ = try WorkspaceSlug("ab")
        }
    }

    @Test("rejects disallowed characters")
    func rejectsInvalidCharacters() {
        #expect(throws: WorkspaceSlugError.invalidCharacters) {
            _ = try WorkspaceSlug("my_lab")
        }
    }

    @Test("rejects leading hyphen")
    func rejectsLeadingHyphen() {
        #expect(throws: WorkspaceSlugError.startsOrEndsWithHyphen) {
            _ = try WorkspaceSlug("-team")
        }
    }

    @Test("rejects reserved words")
    func rejectsReservedWords() {
        #expect(throws: WorkspaceSlugError.reserved("api")) {
            _ = try WorkspaceSlug("API")
        }
    }
}
