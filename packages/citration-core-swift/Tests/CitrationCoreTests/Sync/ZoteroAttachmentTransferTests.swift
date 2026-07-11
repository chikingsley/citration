@testable import CitrationCore
import Foundation
import Testing

// MARK: - ZoteroAttachmentTransferTests

@Suite("Zotero attachment transfer")
struct ZoteroAttachmentTransferTests {
    @Test("File digests stream real bytes and report exact metadata")
    func hashesRealFile() async throws {
        let fixture = try AttachmentTransferFixture()
        defer { fixture.remove() }
        let file = fixture.root.appending(path: "hello.txt")
        try Data("hello".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: file.path
        )

        let digest = try await ZoteroAttachmentFileDigest.read(from: file)

        #expect(digest.md5 == "5d41402abc4b2a76b9719d911017c592")
        #expect(digest.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(digest.size == 5)
        #expect(digest.modificationTimeMilliseconds == 1_700_000_000_000)
    }

    @Test("Remote metadata refresh preserves a verified file and marks changed bytes stale")
    func preservesVerifiedCacheAcrossMetadataRefresh() throws {
        let fixture = try AttachmentTransferFixture()
        defer { fixture.remove() }
        let libraryID = try fixture.database.upsertLibrary(
            identity: .init(type: "user", remoteID: 42),
            name: "Remote Library"
        )
        let itemKey = "ABCD2345"
        let oldMD5 = "5d41402abc4b2a76b9719d911017c592"
        let newMD5 = "7d793037a0760186574b0282f2f435e7"
        let localFile = fixture.root.appending(path: "paper.pdf")
        try Data("hello".utf8).write(to: localFile)
        try fixture.database.storeRemoteItems(
            [fixture.attachment(key: itemKey, version: 1, md5: oldMD5)],
            libraryID: libraryID
        )
        try fixture.database.markAttachmentTransferComplete(
            libraryID: libraryID,
            itemKey: itemKey,
            localURL: localFile,
            md5: oldMD5,
            sha256: "old-sha256",
            remoteMTime: 1_700_000_000_000
        )

        try fixture.database.storeRemoteItems(
            [fixture.attachment(key: itemKey, version: 2, md5: newMD5)],
            libraryID: libraryID
        )

        let stale = try #require(try fixture.database.attachmentCacheRecord(
            libraryID: libraryID,
            itemKey: itemKey
        ))
        #expect(stale.localURL == localFile)
        #expect(stale.cacheState == .stale)
        #expect(stale.remoteMD5 == newMD5)
        #expect(stale.verifiedMD5 == oldMD5)

        try fixture.database.markAttachmentTransferComplete(
            libraryID: libraryID,
            itemKey: itemKey,
            localURL: localFile,
            md5: newMD5,
            sha256: "new-sha256",
            remoteMTime: 1_700_000_001_000
        )
        try fixture.database.storeRemoteItems(
            [fixture.attachment(key: itemKey, version: 3, md5: newMD5)],
            libraryID: libraryID
        )
        let current = try #require(try fixture.database.attachmentCacheRecord(
            libraryID: libraryID,
            itemKey: itemKey
        ))
        #expect(current.cacheState == .downloaded)
        #expect(current.localURL == localFile)
        #expect(current.verifiedMD5 == newMD5)
        #expect(try fixture.database.integrityCheck() == "ok")
    }

    @Test("Transfer failures redact signed URLs before persistence")
    func redactsSignedURLs() throws {
        let fixture = try AttachmentTransferFixture()
        defer { fixture.remove() }
        let libraryID = try fixture.database.upsertLibrary(identity: .init(type: "user", remoteID: 42))
        let itemKey = "ABCD2345"
        try fixture.database.storeRemoteItems(
            [fixture.attachment(key: itemKey, version: 1, md5: "5d41402abc4b2a76b9719d911017c592")],
            libraryID: libraryID
        )
        try fixture.database.markAttachmentTransferFailed(
            libraryID: libraryID,
            itemKey: itemKey,
            operation: "attachment-upload",
            message: "Network failure at https://storage.example.test/object?X-Amz-Signature=secret"
        )
        let failed = try #require(try fixture.database.attachmentCacheRecord(
            libraryID: libraryID,
            itemKey: itemKey
        ))
        #expect(failed.transferError == "Network failure at <redacted-url>")
    }
}

// MARK: - AttachmentTransferFixture

private struct AttachmentTransferFixture {
    // MARK: Lifecycle

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "citration-attachment-transfer-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        database = try CitrationDatabase(at: root.appending(path: "library.sqlite"))
    }

    // MARK: Internal

    let root: URL
    let database: CitrationDatabase

    func attachment(key: String, version: Int64, md5: String) throws -> ZoteroRawObject {
        try ZoteroRawObject(rawValue: .object([
            "key": .string(key),
            "version": .integer(version),
            "data": .object([
                "key": .string(key),
                "version": .integer(version),
                "itemType": .string("attachment"),
                "parentItem": .string("PARENT12"),
                "linkMode": .string("imported_file"),
                "contentType": .string("application/pdf"),
                "charset": .string(""),
                "filename": .string("paper.pdf"),
                "md5": .string(md5),
                "mtime": .integer(1_700_000_000_000 + version),
                "title": .string("paper.pdf"),
                "tags": .array([]),
                "collections": .array([]),
                "relations": .object([:]),
            ]),
        ]))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
