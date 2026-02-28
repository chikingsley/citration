import Testing
import Foundation
@testable import BCStorage

@Suite("BCStorage")
struct BCStorageTests {
	@Test("supabaseS3 rawValue is stable")
	func supabaseRawValueIsStable() {
		#expect(StorageConnectorType.supabaseS3.rawValue == "supabase-s3")
	}

	@Test("LocalObjectStore builds deterministic object key")
	func localStoreBuildsDeterministicObjectKey() async throws {
		let connector = StorageConnector(name: "local", type: .local, bucket: "ignored")
		let store = LocalObjectStore(
			connector: connector,
			baseDirectory: URL(fileURLWithPath: "/tmp/better-cite")
		)

		let itemID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
		let response = try await store.presignUpload(
			request: PresignUploadRequest(
				itemID: itemID,
				filename: "paper.pdf",
				contentType: "application/pdf",
				contentLength: 128
			)
		)

		#expect(response.objectKey == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/paper.pdf")
		#expect(response.uploadURL.path.hasSuffix("/better-cite/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/paper.pdf"))
	}

	@Test("LocalObjectStore rejects negative content length")
	func localStoreRejectsNegativeContentLength() async throws {
		let connector = StorageConnector(name: "local", type: .local, bucket: "ignored")
		let store = LocalObjectStore(
			connector: connector,
			baseDirectory: URL(fileURLWithPath: "/tmp/better-cite")
		)

		await #expect(throws: ObjectStoreError.self) {
			_ = try await store.presignUpload(
				request: PresignUploadRequest(
					itemID: UUID(),
					filename: "paper.pdf",
					contentType: "application/pdf",
					contentLength: -1
				)
			)
		}
	}

	@Test("LocalObjectStore rejects filename path separators")
	func localStoreRejectsFilenamePathSeparators() async throws {
		let connector = StorageConnector(name: "local", type: .local, bucket: "ignored")
		let store = LocalObjectStore(
			connector: connector,
			baseDirectory: URL(fileURLWithPath: "/tmp/better-cite")
		)

		await #expect(throws: ObjectStoreError.self) {
			_ = try await store.presignUpload(
				request: PresignUploadRequest(
					itemID: UUID(),
					filename: "../paper.pdf",
					contentType: "application/pdf",
					contentLength: 123
				)
			)
		}
	}

	@Test("LocalObjectStore validates multipart completion input")
	func localStoreValidatesMultipartCompletionInput() async throws {
		let connector = StorageConnector(name: "local", type: .local, bucket: "ignored")
		let store = LocalObjectStore(
			connector: connector,
			baseDirectory: URL(fileURLWithPath: "/tmp/better-cite")
		)

		await #expect(throws: ObjectStoreError.self) {
			try await store.completeMultipartUpload(
				CompleteMultipartUploadRequest(
					objectKey: "",
					uploadID: "upload-1",
					parts: [UploadedPart(partNumber: 1, etag: "etag-1")]
				)
			)
		}
	}

	@Test("Factory returns LocalObjectStore for local connector")
	func factoryReturnsLocalStoreForLocalConnector() async {
		let factory = AttachmentObjectStoreFactory()
		let connector = StorageConnector(name: "local", type: .local, bucket: "ignored")
		let store = factory.makeStore(
			connector: connector,
			localBaseDirectory: URL(fileURLWithPath: "/tmp/better-cite")
		)

		#expect(store is LocalObjectStore)
	}

	@Test("Factory returns S3CompatibleObjectStore for all remote types",
		  arguments: [StorageConnectorType.s3, .r2, .supabaseS3, .minio])
	func factoryReturnsS3CompatibleStoreForRemoteTypes(type: StorageConnectorType) async {
		let factory = AttachmentObjectStoreFactory()
		let connector = StorageConnector(name: type.rawValue, type: type, bucket: "papers")
		let store = factory.makeStore(
			connector: connector,
			localBaseDirectory: URL(fileURLWithPath: "/tmp/better-cite")
		)

		#expect(store is S3CompatibleObjectStore)
	}

	@Test("S3CompatibleObjectStore throws unsupportedOperation for presignUpload")
	func s3CompatibleStorePresignUploadThrows() async {
		let store = S3CompatibleObjectStore(
			connector: StorageConnector(name: "r2", type: .r2, bucket: "papers")
		)

		await #expect(throws: ObjectStoreError.self) {
			_ = try await store.presignUpload(
				request: PresignUploadRequest(
					itemID: UUID(),
					filename: "paper.pdf",
					contentType: "application/pdf",
					contentLength: 100
				)
			)
		}
	}

	@Test("S3CompatibleObjectStore throws unsupportedOperation for presignDownload")
	func s3CompatibleStorePresignDownloadThrows() async {
		let store = S3CompatibleObjectStore(
			connector: StorageConnector(name: "r2", type: .r2, bucket: "papers")
		)

		await #expect(throws: ObjectStoreError.self) {
			_ = try await store.presignDownload(objectKey: "item/paper.pdf")
		}
	}

	@Test("S3CompatibleObjectStore throws unsupportedOperation for completeMultipart")
	func s3CompatibleStoreCompleteMultipartThrows() async {
		let store = S3CompatibleObjectStore(
			connector: StorageConnector(name: "r2", type: .r2, bucket: "papers")
		)

		await #expect(throws: ObjectStoreError.self) {
			try await store.completeMultipartUpload(
				CompleteMultipartUploadRequest(
					objectKey: "item/paper.pdf",
					uploadID: "upload-1",
					parts: [UploadedPart(partNumber: 1, etag: "etag-1")]
				)
			)
		}
	}

	@Test("S3CompatibleObjectStore throws unsupportedOperation for deleteObject")
	func s3CompatibleStoreDeleteThrows() async {
		let store = S3CompatibleObjectStore(
			connector: StorageConnector(name: "r2", type: .r2, bucket: "papers")
		)

		await #expect(throws: ObjectStoreError.self) {
			try await store.deleteObject(objectKey: "item/paper.pdf")
		}
	}

	@Test("LocalObjectStore rejects object key traversal on download")
	func localStoreRejectsTraversalOnDownload() async throws {
		let connector = StorageConnector(name: "local", type: .local, bucket: "ignored")
		let store = LocalObjectStore(
			connector: connector,
			baseDirectory: URL(fileURLWithPath: "/tmp/better-cite")
		)

		await #expect(throws: ObjectStoreError.self) {
			_ = try await store.presignDownload(objectKey: "../outside.pdf")
		}
	}
}
