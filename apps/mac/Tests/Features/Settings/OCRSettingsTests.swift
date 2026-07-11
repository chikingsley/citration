@testable import Citration
import CitrationCore
import Foundation
import Testing

@MainActor
@Suite("OCR settings")
struct OCRSettingsTests {
    @Test("Mistral credential persists in a real permission-restricted file")
    func credentialFilePermissions() async throws {
        let root = makeTempDirectory()
        defer { cleanupDirectory(root) }
        let keyURL = root.appending(path: "private/mistral-api-key")
        let store = FileAPIKeyStore(fileURL: keyURL)
        let settings = OCRSettingsModel(keyStore: store)

        settings.keyDraft = " fixture-mistral-key\n"
        settings.saveKey()
        try await waitUntil { !settings.isSaving }

        #expect(settings.hasKey)
        #expect(settings.keyDraft.isEmpty)
        #expect(await store.loadAPIKey() == "fixture-mistral-key")
        let attributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)

        settings.clearKey()
        try await waitUntil { !settings.isSaving }
        #expect(!FileManager.default.fileExists(atPath: keyURL.path))
    }
}
