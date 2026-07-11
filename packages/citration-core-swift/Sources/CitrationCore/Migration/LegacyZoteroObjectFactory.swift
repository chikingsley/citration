import CryptoKit
import Foundation

// MARK: - LegacyZoteroObjectFactory

enum LegacyZoteroObjectFactory {
    // MARK: Internal

    static func itemObject(
        _ item: BCItem,
        key: String,
        collectionKeys: [String]
    ) throws -> ZoteroRawObject {
        var data: [String: JSONValue] = [
            "itemType": .string(zoteroItemType(item.itemType)),
            "title": .string(item.title),
            "creators": .array(item.creators.map(creatorValue)),
            "date": .string(item.publicationYear.map(String.init) ?? ""),
            "tags": .array(item.tags.map { .object(["tag": .string($0)]) }),
            "collections": .array(collectionKeys.map(JSONValue.string)),
            "dateAdded": .string(dateString(item.createdAt)),
            "dateModified": .string(dateString(item.updatedAt)),
        ]
        addIdentifiers(item.identifiers, to: &data)
        return try rawObject(key: key, data: data)
    }

    static func collectionObject(
        _ collection: LibraryCollection,
        key: String,
        collectionKeys: [UUID: String]
    ) throws -> ZoteroRawObject {
        try rawObject(key: key, data: [
            "name": .string(collection.name),
            "parentCollection": collection.parentID.flatMap { collectionKeys[$0] }.map(JSONValue.string) ?? .bool(false),
        ])
    }

    static func noteObject(_ note: LibraryNote, key: String, parentKey: String) throws -> ZoteroRawObject {
        try rawObject(key: key, data: [
            "itemType": .string("note"),
            "parentItem": .string(parentKey),
            "note": .string(note.text),
            "tags": .array([]),
            "collections": .array([]),
            "dateAdded": .string(dateString(note.createdAt)),
            "dateModified": .string(dateString(note.updatedAt)),
        ])
    }

    static func attachmentObject(
        legacyKey: String,
        attachment: LegacyAttachmentRecord?,
        key: String,
        parentKey: String
    ) throws -> ZoteroRawObject {
        let filename = attachment?.fileURL.lastPathComponent
            ?? legacyKey.split(separator: "/").last.map(String.init)
            ?? "attachment"
        let createdAt = attachment?.createdAt ?? .distantPast
        return try rawObject(key: key, data: [
            "itemType": .string("attachment"),
            "parentItem": .string(parentKey),
            "linkMode": .string("imported_file"),
            "contentType": .string(attachment?.contentType ?? "application/octet-stream"),
            "filename": .string(filename),
            "title": .string(filename),
            "tags": .array([]),
            "collections": .array([]),
            "dateAdded": .string(dateString(createdAt)),
            "dateModified": .string(dateString(createdAt)),
        ])
    }

    static func annotationObject(
        _ annotation: LibraryAnnotation,
        key: String,
        parentKey: String
    ) throws -> ZoteroRawObject {
        try rawObject(key: key, data: [
            "itemType": .string("annotation"),
            "parentItem": .string(parentKey),
            "annotationType": .string(annotation.kind.rawValue),
            "annotationColor": .string(colorValue(annotation.color)),
            "annotationPageLabel": .string(annotation.location?.pageLabel ?? ""),
            "annotationSortIndex": .string(annotation.location?.sortIndex ?? ""),
            "annotationText": .string(annotation.selectedText ?? ""),
            "annotationComment": .string(annotation.note),
            "annotationPosition": .string(locationJSON(annotation.location)),
            "tags": .array([]),
            "dateAdded": .string(dateString(annotation.createdAt)),
            "dateModified": .string(dateString(annotation.updatedAt)),
        ])
    }

    static func attachmentRecord(
        legacyKey: String,
        attachment: LegacyAttachmentRecord?,
        itemID: UUID,
        objectKey: String
    ) throws -> LegacyMigrationObject {
        let rawPayload: Data = if let attachment {
            try encode(attachment)
        } else {
            try encode(LegacyAttachmentReference(itemID: itemID, attachmentKey: legacyKey))
        }
        return LegacyMigrationObject(
            entityKind: "attachment",
            legacyID: legacyKey,
            rawPayload: rawPayload,
            objectKind: .item,
            objectKey: objectKey
        )
    }

    static func record(
        entityKind: String,
        legacyID: String,
        value: some Encodable,
        objectKind: ZoteroObjectKind? = nil,
        objectKey: String? = nil
    ) throws -> LegacyMigrationObject {
        try LegacyMigrationObject(
            entityKind: entityKind,
            legacyID: legacyID,
            rawPayload: encode(value),
            objectKind: objectKind,
            objectKey: objectKey
        )
    }

    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func requiredItemKey(_ id: UUID, in keys: [UUID: String]) throws -> String {
        guard let key = keys[id] else {
            throw LegacyLibraryMigrationError.missingItem(id, entityKind: "reference")
        }
        return key
    }

    static func itemKey(for id: UUID) -> String {
        "legacy-item-\(id.uuidString.lowercased())"
    }

    static func collectionKey(for id: UUID) -> String {
        "legacy-collection-\(id.uuidString.lowercased())"
    }

    static func noteKey(for id: UUID) -> String {
        "legacy-note-\(id.uuidString.lowercased())"
    }

    static func annotationKey(for id: UUID) -> String {
        "legacy-annotation-\(id.uuidString.lowercased())"
    }

    static func attachmentKey(for legacyKey: String) -> String {
        let digest = SHA256.hash(data: Data(legacyKey.utf8))
        return "legacy-attachment-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Private

    private static func rawObject(key: String, data: [String: JSONValue]) throws -> ZoteroRawObject {
        var completeData = data
        completeData["key"] = .string(key)
        completeData["version"] = .integer(0)
        return try ZoteroRawObject(rawValue: .object([
            "key": .string(key),
            "version": .integer(0),
            "data": .object(completeData),
        ]))
    }

    private static func addIdentifiers(
        _ identifiers: [Identifier],
        to data: inout [String: JSONValue]
    ) {
        for identifier in identifiers {
            switch identifier.type {
            case .doi:
                data["DOI"] = data["DOI"] ?? .string(identifier.value)

            case .isbn:
                data["ISBN"] = data["ISBN"] ?? .string(identifier.value)

            case .pmid:
                data["PMID"] = data["PMID"] ?? .string(identifier.value)

            case .arxiv:
                data["archive"] = data["archive"] ?? .string("arXiv")
                data["archiveLocation"] = data["archiveLocation"] ?? .string(identifier.value)

            case .url:
                data["url"] = data["url"] ?? .string(identifier.value)
            }
        }
    }

    private static func zoteroItemType(_ itemType: ItemType) -> String {
        switch itemType {
        case .article: "journalArticle"
        case .book: "book"
        case .preprint: "preprint"
        case .thesis: "thesis"
        case .dataset: "dataset"
        case .webpage: "webpage"
        case .unknown: "document"
        }
    }

    private static func creatorValue(_ creator: Creator) -> JSONValue {
        if let literalName = creator.literalName, !literalName.isEmpty {
            return .object(["creatorType": .string("author"), "name": .string(literalName)])
        }
        return .object([
            "creatorType": .string("author"),
            "firstName": .string(creator.givenName ?? ""),
            "lastName": .string(creator.familyName ?? ""),
        ])
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func colorValue(_ color: AnnotationColor) -> String {
        switch color {
        case .yellow: "#ffd400"
        case .green: "#5fb236"
        case .blue: "#2ea8e5"
        case .pink: "#e56eee"
        case .purple: "#a28ae5"
        }
    }

    private static func locationJSON(_ location: ReaderLocation?) throws -> String {
        guard let location else {
            return "{}"
        }
        let value: JSONValue = switch location {
        case let .page(page):
            .object(["pageIndex": .integer(Int64(max(page - 1, 0)))])
        case let .epubCFI(cfi):
            .object(["epubCFI": .string(cfi)])
        case let .textOffset(offset):
            .object(["textOffset": .integer(Int64(offset))])
        case let .time(seconds):
            .object(["seconds": .number(seconds)])
        }
        let data = try ZoteroJSON.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - LegacyAttachmentReference

private struct LegacyAttachmentReference: Codable {
    let itemID: UUID
    let attachmentKey: String
}

private extension ReaderLocation {
    var pageLabel: String? {
        guard case let .page(number) = self else {
            return nil
        }
        return String(number)
    }

    var sortIndex: String? {
        switch self {
        case let .page(number):
            String(format: "%08d", max(number, 0))
        case let .epubCFI(cfi):
            cfi
        case let .textOffset(offset):
            String(format: "%012d", max(offset, 0))
        case let .time(seconds):
            String(format: "%016.3f", max(seconds, 0))
        }
    }
}
