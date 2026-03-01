import Testing
import Foundation
@testable import BCDataRemote

@Suite("AuthSession")
struct AuthSessionTests {
    @Test("reports expiration against reference date")
    func expirationChecks() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 1_500)
        )

        #expect(session.isExpired(referenceDate: now) == false)
        #expect(session.isExpired(referenceDate: Date(timeIntervalSince1970: 1_500)) == true)
    }

    @Test("in-memory session store supports load/save/clear")
    func inMemoryStoreLifecycle() async {
        let store = InMemoryAuthSessionStore()
        #expect(await store.loadSession() == nil)

        let session = AuthSession(
            accessToken: "token-a",
            refreshToken: "token-r",
            expiresAt: Date(timeIntervalSince1970: 10_000)
        )

        await store.saveSession(session)
        #expect(await store.loadSession() == session)

        await store.saveSession(nil)
        #expect(await store.loadSession() == nil)
    }
}
