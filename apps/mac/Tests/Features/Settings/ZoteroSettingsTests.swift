@testable import Citration
import CitrationCore
import Foundation
import Testing

@MainActor
@Suite("Zotero settings")
struct ZoteroSettingsTests {
    @Test("The running app switches between real local and remote SQLite libraries")
    func runningLibrarySelection() async throws {
        let localItem = BCItem(title: "Local Fixture")
        let remoteItem = BCItem(title: "Remote Fixture")
        let model = makeAppModel(initialItems: [localItem])
        let remoteFiles = makeTempDirectory()
        defer { cleanupDirectory(remoteFiles) }
        let profile = try ZoteroConnectionProfile(
            serverURL: #require(URL(string: "https://sync.example.test/")),
            userID: 42,
            username: "fixture-user",
            displayName: "Remote Fixture Library",
            canWrite: true,
            canAccessFiles: true
        )
        let remoteStore = try CitrationLibraryStore(
            database: model.database,
            attachmentsDirectory: remoteFiles.appending(path: "attachments", directoryHint: .isDirectory),
            libraryIdentity: profile.libraryIdentity,
            libraryName: profile.displayName
        )
        await remoteStore.upsert(remoteItem)

        try await model.activateLibrary(profile)
        try await waitUntil {
            model.items.map(\.title) == [remoteItem.title]
        }

        try await model.activateLocalLibrary()
        try await waitUntil {
            model.items.map(\.title) == [localItem.title]
        }
    }

    @Test("Settings reflect the durable connection profile without reading a secret from SQLite")
    func durableConfiguration() async throws {
        let model = makeAppModel()
        let profile = try ZoteroConnectionProfile(
            serverURL: #require(URL(string: "https://sync.example.test/")),
            userID: 42,
            username: "fixture-user",
            displayName: "Remote Fixture Library",
            canWrite: true,
            canAccessFiles: false
        )
        try model.database.saveZoteroConnectionProfile(profile)

        await model.zoteroSettings.refresh()

        #expect(model.zoteroSettings.profile == profile)
        #expect(model.zoteroSettings.serverURLDraft == "https://sync.example.test/")
        #expect(model.zoteroSettings.apiKeyDraft.isEmpty)
    }
}
