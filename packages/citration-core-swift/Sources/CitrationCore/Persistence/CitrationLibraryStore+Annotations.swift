import Foundation
import GRDB

public extension CitrationLibraryStore {
    func annotationContext(
        itemID: UUID,
        attachmentKey: String
    ) throws -> SynchronizedLibraryAnnotationContext {
        let row = try database.databaseQueue.read { database in
            try Row.fetchOne(
                database,
                sql: """
                SELECT attachment_identity.app_uuid AS attachment_uuid,
                    parent_identity.app_uuid AS parent_uuid,
                    attachment.parent_item_key AS parent_key
                FROM attachment_projections attachment
                JOIN app_object_identity attachment_identity
                  ON attachment_identity.library_id = attachment.library_id
                 AND attachment_identity.object_kind = 'item'
                 AND attachment_identity.object_key = attachment.item_key
                JOIN app_object_identity parent_identity
                  ON parent_identity.library_id = attachment.library_id
                 AND parent_identity.object_kind = 'item'
                 AND parent_identity.object_key = attachment.parent_item_key
                WHERE attachment.library_id = ? AND attachment.item_key = ?
                  AND parent_identity.app_uuid = ?
                """,
                arguments: [libraryID, attachmentKey, itemID.uuidString]
            )
        }
        guard let row else {
            throw AnnotationEditingError.attachmentMismatch
        }
        let attachmentText: String = row["attachment_uuid"]
        let parentText: String = row["parent_uuid"]
        guard
            let attachmentID = UUID(uuidString: attachmentText),
            let parentID = UUID(uuidString: parentText)
        else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        return SynchronizedLibraryAnnotationContext(
            parentAttachmentIdentity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: attachmentKey,
                appUUID: attachmentID
            ),
            bibliographicItemIdentity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: row["parent_key"],
                appUUID: parentID
            )
        )
    }

    func listAnnotations(
        itemID: UUID,
        attachmentKey: String?
    ) throws -> [LibraryAnnotation] {
        try listSynchronizedAnnotations(itemID: itemID, attachmentKey: attachmentKey)
            .map { $0.compatibilityAnnotation() }
    }

    func listSynchronizedAnnotations(
        itemID: UUID,
        attachmentKey: String?
    ) throws -> [SynchronizedLibraryAnnotation] {
        try database.databaseQueue.read { database in
            var arguments: StatementArguments = [libraryID, itemID.uuidString]
            var attachmentClause = ""
            if let attachmentKey {
                attachmentClause = "AND annotation.parent_item_key = ?"
                arguments += [attachmentKey]
            }
            return try Row.fetchAll(
                database,
                sql: """
                SELECT annotation.*, identity.app_uuid,
                    attachment_identity.app_uuid AS attachment_uuid,
                    parent_identity.app_uuid AS parent_uuid,
                    attachment.parent_item_key AS bibliographic_item_key,
                    object.object_version, object.sync_state,
                    (SELECT text_value FROM item_fields field
                     WHERE field.library_id = annotation.library_id AND field.item_key = annotation.item_key
                       AND field.field_name = 'dateAdded') AS date_added,
                    (SELECT text_value FROM item_fields field
                     WHERE field.library_id = annotation.library_id AND field.item_key = annotation.item_key
                       AND field.field_name = 'dateModified') AS date_modified
                FROM annotation_projections annotation
                JOIN app_object_identity identity
                  ON identity.library_id = annotation.library_id
                 AND identity.object_kind = 'item'
                 AND identity.object_key = annotation.item_key
                JOIN attachment_projections attachment
                  ON attachment.library_id = annotation.library_id
                 AND attachment.item_key = annotation.parent_item_key
                JOIN app_object_identity attachment_identity
                  ON attachment_identity.library_id = attachment.library_id
                 AND attachment_identity.object_kind = 'item'
                 AND attachment_identity.object_key = attachment.item_key
                JOIN app_object_identity parent_identity
                  ON parent_identity.library_id = attachment.library_id
                 AND parent_identity.object_kind = 'item'
                 AND parent_identity.object_key = attachment.parent_item_key
                JOIN zotero_objects object
                  ON object.library_id = annotation.library_id
                 AND object.object_kind = 'item'
                 AND object.object_key = annotation.item_key
                WHERE annotation.library_id = ? AND parent_identity.app_uuid = ? \(attachmentClause)
                ORDER BY annotation.sort_index, date_modified DESC
                """,
                arguments: arguments
            ).map { row in
                try Self.decodeSynchronizedAnnotation(row, database: database)
            }
        }
    }

    func upsert(_ input: LibraryAnnotation) throws -> LibraryAnnotation {
        let synchronized = try listSynchronizedAnnotations(
            itemID: input.itemID,
            attachmentKey: input.attachmentKey
        ).first { $0.identity.appUUID == input.id }
        if let synchronized {
            return try updateSynchronizedAnnotation(
                SynchronizedLibraryAnnotationUpdate(
                    identity: synchronized.identity,
                    kind: input.kind,
                    color: input.color,
                    comment: input.note,
                    tags: synchronized.tags
                )
            ).compatibilityAnnotation()
        }

        var annotation = input
        annotation.updatedAt = .now
        let key = try objectKey(for: annotation.id, kind: .item)
            ?? LegacyZoteroObjectFactory.annotationKey(for: annotation.id)
        let object = try LegacyZoteroObjectFactory.annotationObject(
            annotation,
            key: key,
            parentKey: annotation.attachmentKey
        )
        try database.storeLocalItems([object], libraryID: libraryID)
        try upsertIdentity(
            uuid: annotation.id,
            kind: .item,
            key: key,
            createdAt: annotation.createdAt,
            updatedAt: annotation.updatedAt
        )
        return try listAnnotations(itemID: annotation.itemID, attachmentKey: annotation.attachmentKey)
            .first { $0.id == annotation.id } ?? annotation
    }

    func createSynchronizedAnnotation(
        _ draft: SynchronizedLibraryAnnotationDraft
    ) throws -> SynchronizedLibraryAnnotation {
        try validate(draft)
        let key = LegacyZoteroObjectFactory.annotationKey(for: draft.id)
        let createdAt = draft.createdAt
        let object = try Self.annotationObject(draft, key: key, modifiedAt: createdAt)
        try database.storeLocalItems([object], libraryID: libraryID)
        try upsertIdentity(
            uuid: draft.id,
            kind: .item,
            key: key,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        return try synchronizedAnnotation(
            identity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: key,
                appUUID: draft.id
            ),
            bibliographicItemID: draft.bibliographicItemIdentity.appUUID,
            attachmentKey: draft.parentAttachmentIdentity.objectKey
        )
    }

    func updateSynchronizedAnnotation(
        _ update: SynchronizedLibraryAnnotationUpdate
    ) throws -> SynchronizedLibraryAnnotation {
        guard
            update.identity.libraryID == libraryID,
            try objectKey(for: update.identity.appUUID, kind: .item) == update.identity.objectKey
        else {
            throw AnnotationEditingError.identityMismatch
        }
        guard update.kind != .ink else {
            throw AnnotationEditingError.invalidAnnotationType
        }
        let existing = try database.databaseQueue.read { database in
            try Row.fetchOne(
                database,
                sql: """
                SELECT parent_identity.app_uuid AS bibliographic_uuid,
                    annotation.parent_item_key AS attachment_key
                FROM annotation_projections annotation
                JOIN attachment_projections attachment
                  ON attachment.library_id = annotation.library_id
                 AND attachment.item_key = annotation.parent_item_key
                JOIN app_object_identity parent_identity
                  ON parent_identity.library_id = attachment.library_id
                 AND parent_identity.object_kind = 'item'
                 AND parent_identity.object_key = attachment.parent_item_key
                WHERE annotation.library_id = ? AND annotation.item_key = ?
                """,
                arguments: [libraryID, update.identity.objectKey]
            )
        }
        guard let existing else {
            throw AnnotationEditingError.itemNotFound
        }
        let bibliographicText: String = existing["bibliographic_uuid"]
        guard let bibliographicID = UUID(uuidString: bibliographicText) else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        let attachmentKey: String = existing["attachment_key"]
        _ = try database.updateLocalItemFields(
            libraryID: libraryID,
            key: update.identity.objectKey,
            updates: [
                ZoteroItemFieldUpdate(field: "annotationType", value: .string(update.kind.rawValue)),
                ZoteroItemFieldUpdate(field: "annotationColor", value: .string(update.color.zoteroHex)),
                ZoteroItemFieldUpdate(field: "annotationComment", value: .string(update.comment)),
                ZoteroItemFieldUpdate(field: "tags", value: .array(Self.tagValues(update.tags))),
            ]
        )
        return try synchronizedAnnotation(
            identity: update.identity,
            bibliographicItemID: bibliographicID,
            attachmentKey: attachmentKey
        )
    }

    private static func decodeSynchronizedAnnotation(
        _ row: Row,
        database: Database
    ) throws -> SynchronizedLibraryAnnotation {
        let libraryID: Int64 = row["library_id"]
        let itemKey: String = row["item_key"]
        let attachmentKey: String = row["parent_item_key"]
        let idText: String = row["app_uuid"]
        let attachmentText: String = row["attachment_uuid"]
        let parentText: String = row["parent_uuid"]
        guard
            let id = UUID(uuidString: idText),
            let attachmentID = UUID(uuidString: attachmentText),
            let itemID = UUID(uuidString: parentText)
        else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        let syncStateValue: String = row["sync_state"]
        guard let syncState = ZoteroSyncState(rawValue: syncStateValue) else {
            throw CitrationDatabaseError.unknownSyncState(syncStateValue)
        }
        return try SynchronizedLibraryAnnotation(
            identity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: itemKey,
                appUUID: id
            ),
            parentAttachmentIdentity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: attachmentKey,
                appUUID: attachmentID
            ),
            bibliographicItemIdentity: SynchronizedLibraryItemIdentity(
                libraryID: libraryID,
                objectKey: row["bibliographic_item_key"],
                appUUID: itemID
            ),
            version: row["object_version"],
            syncState: syncState,
            type: row["annotation_type"],
            color: row["color"],
            pageLabel: row["page_label"],
            sortIndex: row["sort_index"],
            text: row["annotation_text"],
            comment: row["annotation_comment"],
            positionJSON: row["position_json"],
            tags: CitrationDatabase.fetchTags(libraryID: libraryID, key: itemKey, database: database),
            createdAt: parseDate(row["date_added"]) ?? .distantPast,
            updatedAt: parseDate(row["date_modified"]) ?? .distantPast
        )
    }

    private func validate(_ draft: SynchronizedLibraryAnnotationDraft) throws {
        guard try objectKey(for: draft.id, kind: .item) == nil else {
            throw AnnotationEditingError.duplicateIdentity
        }
        guard
            draft.parentAttachmentIdentity.libraryID == libraryID,
            draft.bibliographicItemIdentity.libraryID == libraryID,
            try objectKey(for: draft.parentAttachmentIdentity.appUUID, kind: .item)
            == draft.parentAttachmentIdentity.objectKey,
            try objectKey(for: draft.bibliographicItemIdentity.appUUID, kind: .item)
            == draft.bibliographicItemIdentity.objectKey
        else {
            throw AnnotationEditingError.identityMismatch
        }
        let parentKey = try database.databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: """
                SELECT parent_item_key FROM attachment_projections
                WHERE library_id = ? AND item_key = ?
                """,
                arguments: [libraryID, draft.parentAttachmentIdentity.objectKey]
            )
        }
        guard parentKey == draft.bibliographicItemIdentity.objectKey else {
            throw AnnotationEditingError.attachmentMismatch
        }
        guard
            let data = draft.positionJSON.data(using: .utf8),
            let position = try ZoteroJSON.decode(data).objectValue,
            !position.isEmpty,
            !draft.sortIndex.isEmpty
        else {
            throw AnnotationEditingError.invalidPosition
        }
        if draft.kind == .ink {
            guard
                position["pageIndex"]?.integerValue != nil,
                position["width"]?.numberValue ?? 0 > 0,
                position["paths"]?.arrayValue?.isEmpty == false
            else {
                throw AnnotationEditingError.invalidPosition
            }
        }
    }

    private func synchronizedAnnotation(
        identity: SynchronizedLibraryItemIdentity,
        bibliographicItemID: UUID,
        attachmentKey: String
    ) throws -> SynchronizedLibraryAnnotation {
        guard
            let annotation = try listSynchronizedAnnotations(
                itemID: bibliographicItemID,
                attachmentKey: attachmentKey
            ).first(where: { $0.identity == identity })
        else {
            throw AnnotationEditingError.itemNotFound
        }
        return annotation
    }

    private static func annotationObject(
        _ draft: SynchronizedLibraryAnnotationDraft,
        key: String,
        modifiedAt: Date
    ) throws -> ZoteroRawObject {
        let date = ISO8601DateFormatter().string(from: modifiedAt)
        var data: [String: JSONValue] = [
            "key": .string(key),
            "version": .integer(0),
            "itemType": .string("annotation"),
            "parentItem": .string(draft.parentAttachmentIdentity.objectKey),
            "annotationType": .string(draft.kind.rawValue),
            "annotationColor": .string(draft.color.zoteroHex),
            "annotationPageLabel": .string(draft.pageLabel),
            "annotationSortIndex": .string(draft.sortIndex),
            "annotationComment": .string(draft.comment),
            "annotationPosition": .string(draft.positionJSON),
            "tags": .array(tagValues(draft.tags)),
            "dateAdded": .string(date),
            "dateModified": .string(date),
        ]
        if draft.kind == .highlight || draft.kind == .underline {
            data["annotationText"] = .string(draft.text)
        }
        return try ZoteroRawObject(rawValue: .object([
            "key": .string(key),
            "version": .integer(0),
            "data": .object(data),
        ]))
    }

    private static func tagValues(_ tags: [ZoteroProjectedTag]) -> [JSONValue] {
        tags.sorted { $0.position < $1.position }.map { tag in
            var object = ["tag": JSONValue.string(tag.value)]
            if let type = tag.type {
                object["type"] = .integer(Int64(type))
            }
            return .object(object)
        }
    }
}
