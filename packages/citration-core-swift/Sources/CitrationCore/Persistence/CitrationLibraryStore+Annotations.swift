import Foundation
import GRDB

extension CitrationLibraryStore {
    public func listAnnotations(
        itemID: UUID,
        attachmentKey: String?
    ) throws -> [LibraryAnnotation] {
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
                SELECT annotation.*, identity.app_uuid, parent_identity.app_uuid AS parent_uuid,
                    (SELECT text_value FROM item_fields field
                     WHERE field.library_id = annotation.library_id AND field.item_key = annotation.item_key
                       AND field.field_name = 'dateAdded') AS date_added,
                    (SELECT text_value FROM item_fields field
                     WHERE field.library_id = annotation.library_id AND field.item_key = annotation.item_key
                       AND field.field_name = 'dateModified') AS date_modified
                FROM annotation_projections annotation
                JOIN app_object_identity identity
                  ON identity.library_id = annotation.library_id
                 AND identity.object_key = annotation.item_key
                JOIN attachment_projections attachment
                  ON attachment.library_id = annotation.library_id
                 AND attachment.item_key = annotation.parent_item_key
                JOIN app_object_identity parent_identity
                  ON parent_identity.library_id = attachment.library_id
                 AND parent_identity.object_key = attachment.parent_item_key
                WHERE annotation.library_id = ? AND parent_identity.app_uuid = ? \(attachmentClause)
                ORDER BY annotation.sort_index, date_modified DESC
                """,
                arguments: arguments
            ).compactMap(Self.decodeAnnotation)
        }
    }

    public func upsert(_ input: LibraryAnnotation) throws -> LibraryAnnotation {
        let existing = try listAnnotations(itemID: input.itemID, attachmentKey: input.attachmentKey)
            .first { $0.id == input.id }
        var annotation = input
        annotation.createdAt = existing?.createdAt ?? input.createdAt
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

    private static func decodeAnnotation(_ row: Row) -> LibraryAnnotation? {
        let idText: String = row["app_uuid"]
        let parentText: String = row["parent_uuid"]
        guard let id = UUID(uuidString: idText), let itemID = UUID(uuidString: parentText) else {
            return nil
        }
        return LibraryAnnotation(
            id: id,
            itemID: itemID,
            attachmentKey: row["parent_item_key"],
            kind: AnnotationKind(rawValue: row["annotation_type"]) ?? .note,
            location: location(from: row["position_json"]),
            selectedText: row["annotation_text"],
            note: row["annotation_comment"],
            color: annotationColor(from: row["color"]),
            createdAt: parseDate(row["date_added"]) ?? .distantPast,
            updatedAt: parseDate(row["date_modified"]) ?? .distantPast
        )
    }

    private static func location(from positionJSON: String) -> ReaderLocation? {
        guard
            let data = positionJSON.data(using: .utf8),
            let object = try? ZoteroJSON.decode(data).objectValue
        else {
            return nil
        }
        if let pageIndex = object["pageIndex"]?.integerValue {
            return .page(Int(pageIndex) + 1)
        }
        if let cfi = object["epubCFI"]?.stringValue {
            return .epubCFI(cfi)
        }
        if let offset = object["textOffset"]?.integerValue {
            return .textOffset(Int(offset))
        }
        if let seconds = object["seconds"]?.numberValue {
            return .time(seconds: seconds)
        }
        return nil
    }

    private static func annotationColor(from value: String) -> AnnotationColor {
        switch value.lowercased() {
        case "#5fb236",
             "green": .green
        case "#2ea8e5",
             "blue": .blue
        case "#e56eee",
             "pink": .pink
        case "#a28ae5",
             "purple": .purple
        default: .yellow
        }
    }
}
