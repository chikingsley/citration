@testable import CitrationCore
import Foundation
import Testing

// MARK: - SynchronizedObjectStoreTests

@Suite("Synchronized GRDB object projections")
struct SynchronizedObjectStoreTests {
    // MARK: Internal

    @Test("Synchronized notes retain HTML, parent identity, tags, keys, and versions")
    func synchronizedNotesRetainZoteroContract() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let (libraryID, _, store) = try fixture.makeRemoteStore()

        let note = try #require(try await store.listSynchronizedNotes(itemID: nil).first)
        let object = try #require(try fixture.database.fetchObject(
            libraryID: libraryID,
            kind: .item,
            key: note.identity.objectKey
        ))

        #expect(!note.html.isEmpty)
        #expect(note.identity.libraryID == libraryID)
        #expect(note.parentIdentity.libraryID == libraryID)
        #expect(!note.parentIdentity.objectKey.isEmpty)
        #expect(note.version == object.version)
        #expect(note.syncState == .synced)
        let projectedNote = try fixture.database.fetchProjectedItem(
            libraryID: libraryID,
            key: note.identity.objectKey
        )
        #expect(note.tags == projectedNote?.tags)
    }

    @Test("Synchronized annotations retain exact Zotero identity, geometry, and metadata")
    func synchronizedAnnotationsRetainZoteroContract() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let (libraryID, items, store) = try fixture.makeRemoteStore()
        let rawAnnotation = try #require(items.first { $0.itemType == "annotation" })
        let annotationKey = try #require(rawAnnotation.key)
        let attachmentKey = try #require(rawAnnotation.data["parentItem"]?.stringValue)
        let rawAttachment = try #require(items.first { $0.key == attachmentKey })
        let bibliographicKey = try #require(rawAttachment.data["parentItem"]?.stringValue)
        let bibliographicItem = try #require(
            await store.listLibraryItems().first { $0.identity.objectKey == bibliographicKey }
        )

        let annotation = try #require(
            try await store.listSynchronizedAnnotations(
                itemID: bibliographicItem.identity.appUUID,
                attachmentKey: attachmentKey
            ).first { $0.identity.objectKey == annotationKey }
        )

        #expect(annotation.version == rawAnnotation.version)
        #expect(annotation.syncState == .synced)
        #expect(annotation.parentAttachmentIdentity.objectKey == attachmentKey)
        #expect(annotation.bibliographicItemIdentity.objectKey == bibliographicKey)
        #expect(annotation.type == rawAnnotation.data["annotationType"]?.stringValue)
        #expect(annotation.pageLabel == rawAnnotation.data["annotationPageLabel"]?.stringValue)
        #expect(annotation.sortIndex == rawAnnotation.data["annotationSortIndex"]?.stringValue)
        #expect(annotation.text == (rawAnnotation.data["annotationText"]?.stringValue ?? ""))
        #expect(annotation.comment == (rawAnnotation.data["annotationComment"]?.stringValue ?? ""))
        #expect(annotation.positionJSON == rawAnnotation.data["annotationPosition"]?.stringValue)
        #expect(annotation.pageIndex != nil)
        #expect(!annotation.rects.isEmpty || annotation.kind == .ink)
        let projectedAnnotation = try fixture.database.fetchProjectedItem(
            libraryID: libraryID,
            key: annotationKey
        )
        #expect(annotation.tags == projectedAnnotation?.tags)
    }

    @Test("Zotero-compatible annotation creation stores exact geometry and ordering")
    func synchronizedAnnotationCreationStoresExactContract() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let (libraryID, _, store) = try fixture.makeRemoteStore()
        let context = try await firstAnnotationContext(in: store)
        let id = UUID()
        let positionJSON = "{\"nextPageRects\":[[10,700,80,714]],\"pageIndex\":0,\"rects\":[[72,100,180,114]]}"

        let draft = SynchronizedLibraryAnnotationDraft(
            id: id,
            parentAttachmentIdentity: context.parentAttachmentIdentity,
            bibliographicItemIdentity: context.bibliographicItemIdentity,
            kind: .highlight,
            color: .green,
            pageLabel: "1",
            sortIndex: "00000|000123|00678",
            text: "Exact selected text",
            comment: "Created in Citration",
            positionJSON: positionJSON,
            tags: [ZoteroProjectedTag(position: 0, value: "review", type: nil)]
        )
        let annotation = try await store.createSynchronizedAnnotation(draft)

        #expect(annotation.identity.appUUID == id)
        #expect(annotation.identity.libraryID == libraryID)
        #expect(annotation.syncState == .dirty)
        #expect(annotation.version == 0)
        #expect(annotation.positionJSON == positionJSON)
        #expect(annotation.rects.count == 1)
        #expect(annotation.nextPageRects.count == 1)
        #expect(annotation.sortIndex == "00000|000123|00678")
        #expect(annotation.tags.map(\.value) == ["review"])
        await #expect(throws: AnnotationEditingError.duplicateIdentity) {
            try await store.createSynchronizedAnnotation(draft)
        }
    }

    @Test("Annotation edits preserve geometry, text, versions, pristine data, and unknown fields")
    func synchronizedAnnotationEditsAreLossless() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let (libraryID, _, store) = try fixture.makeRemoteStore()
        let annotation = try await firstAnnotation(in: store)
        let before = try #require(try fixture.database.fetchObject(
            libraryID: libraryID,
            kind: .item,
            key: annotation.identity.objectKey
        ))
        let beforeData = try #require(before.current.objectValue?["data"]?.objectValue)

        let updated = try await store.updateSynchronizedAnnotation(
            SynchronizedLibraryAnnotationUpdate(
                identity: annotation.identity,
                kind: annotation.kind == .underline ? .highlight : .underline,
                color: .purple,
                comment: "A revised comment",
                tags: [ZoteroProjectedTag(position: 0, value: "revised", type: nil)]
            )
        )
        let after = try #require(try fixture.database.fetchObject(
            libraryID: libraryID,
            kind: .item,
            key: annotation.identity.objectKey
        ))
        let afterData = try #require(after.current.objectValue?["data"]?.objectValue)

        #expect(updated.syncState == .dirty)
        #expect(updated.version == annotation.version)
        #expect(updated.positionJSON == annotation.positionJSON)
        #expect(updated.text == annotation.text)
        #expect(updated.comment == "A revised comment")
        #expect(updated.color == AnnotationColor.purple.zoteroHex)
        #expect(updated.tags.map(\.value) == ["revised"])
        #expect(after.version == before.version)
        #expect(after.pristine == before.current)
        #expect(afterData["annotationPosition"] == beforeData["annotationPosition"])
        #expect(afterData["annotationText"] == beforeData["annotationText"])
        #expect(afterData["annotationSortIndex"] == beforeData["annotationSortIndex"])
        #expect(afterData["parentItem"] == beforeData["parentItem"])
        #expect(afterData["relations"] == beforeData["relations"])
    }

    // MARK: Private

    private func firstAnnotationContext(
        in store: CitrationLibraryStore
    ) async throws -> SynchronizedLibraryAnnotationContext {
        let annotation = try await firstAnnotation(in: store)
        return SynchronizedLibraryAnnotationContext(
            parentAttachmentIdentity: annotation.parentAttachmentIdentity,
            bibliographicItemIdentity: annotation.bibliographicItemIdentity
        )
    }

    private func firstAnnotation(
        in store: CitrationLibraryStore
    ) async throws -> SynchronizedLibraryAnnotation {
        for item in await store.listLibraryItems() {
            if
                let annotation = try await store.listSynchronizedAnnotations(
                    itemID: item.identity.appUUID,
                    attachmentKey: nil
                ).first
            {
                return annotation
            }
        }
        throw AnnotationEditingError.itemNotFound
    }
}

private extension StoreFixture {
    func makeRemoteStore() throws -> (Int64, [ZoteroRawObject], CitrationLibraryStore) {
        let identity = ZoteroLibraryIdentity(type: "user", remoteID: 42)
        let libraryID = try database.upsertLibrary(identity: identity, name: "Remote Fixture")
        let items = try capturedItems()
        try database.storeRemoteCollections(capturedCollections(), libraryID: libraryID)
        try database.storeRemoteItems(items, libraryID: libraryID)
        try database.ensureAppIdentities(collections: [], items: items, libraryID: libraryID)
        let store = try CitrationLibraryStore(
            database: database,
            attachmentsDirectory: root.appending(path: "remote-attachments", directoryHint: .isDirectory),
            libraryIdentity: identity,
            libraryName: "Remote Fixture"
        )
        return (libraryID, items, store)
    }
}
