import Foundation

// MARK: - LegacyZoteroConversion

enum LegacyZoteroConversion {
    // MARK: Internal

    static func project(_ snapshot: LegacyLibrarySnapshot) throws -> LegacyMigrationProjection {
        try validate(snapshot)
        var context = ProjectionContext(snapshot: snapshot)
        try projectCollections(in: &context)
        try projectItems(in: &context)
        try projectMemberships(in: &context)
        try projectNotes(in: &context)
        try projectAttachments(in: &context)
        try projectAnnotations(in: &context)
        try projectRelationships(in: &context)
        try projectReaderProgress(in: &context)
        return LegacyMigrationProjection(
            collections: context.collections,
            items: context.items,
            records: context.records,
            relationships: context.relationships,
            readerProgress: context.readerProgress,
            attachmentPaths: context.attachmentPaths
        )
    }

    // MARK: Private

    private static func projectCollections(in context: inout ProjectionContext) throws {
        for collection in context.snapshot.collections.collections {
            let key = context.collectionKeys[collection.id]
                ?? LegacyZoteroObjectFactory.collectionKey(for: collection.id)
            try context.records.append(LegacyZoteroObjectFactory.record(
                entityKind: "collection",
                legacyID: collection.id.uuidString,
                value: collection,
                objectKind: .collection,
                objectKey: key
            ))
            try context.collections.append(LegacyZoteroObjectFactory.collectionObject(
                collection,
                key: key,
                collectionKeys: context.collectionKeys
            ))
        }
    }

    private static func projectItems(in context: inout ProjectionContext) throws {
        for item in context.snapshot.items {
            let key = try LegacyZoteroObjectFactory.requiredItemKey(item.id, in: context.itemKeys)
            try context.records.append(LegacyZoteroObjectFactory.record(
                entityKind: "item",
                legacyID: item.id.uuidString,
                value: item,
                objectKind: .item,
                objectKey: key
            ))
            let memberships = context.memberships[item.id, default: []]
            try context.items.append(LegacyZoteroObjectFactory.itemObject(
                item,
                key: key,
                collectionKeys: memberships.compactMap { context.collectionKeys[$0.collectionID] }
            ))
        }
    }

    private static func projectMemberships(in context: inout ProjectionContext) throws {
        for membership in context.snapshot.collections.memberships {
            try context.records.append(LegacyZoteroObjectFactory.record(
                entityKind: "membership",
                legacyID: membership.id.uuidString,
                value: membership
            ))
        }
    }

    private static func projectNotes(in context: inout ProjectionContext) throws {
        for note in context.snapshot.notes {
            let key = LegacyZoteroObjectFactory.noteKey(for: note.id)
            try context.records.append(LegacyZoteroObjectFactory.record(
                entityKind: "note",
                legacyID: note.id.uuidString,
                value: note,
                objectKind: .item,
                objectKey: key
            ))
            try context.items.append(LegacyZoteroObjectFactory.noteObject(
                note,
                key: key,
                parentKey: LegacyZoteroObjectFactory.requiredItemKey(note.itemID, in: context.itemKeys)
            ))
        }
    }

    private static func projectAttachments(in context: inout ProjectionContext) throws {
        let stored = Dictionary(
            context.snapshot.attachments.map { ($0.attachmentKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for legacyKey in context.attachmentKeys.keys.sorted() {
            let attachment = stored[legacyKey]
            guard let itemID = context.itemID(forAttachmentKey: legacyKey) else {
                continue
            }
            let key = context.attachmentKeys[legacyKey]
                ?? LegacyZoteroObjectFactory.attachmentKey(for: legacyKey)
            try context.records.append(LegacyZoteroObjectFactory.attachmentRecord(
                legacyKey: legacyKey,
                attachment: attachment,
                itemID: itemID,
                objectKey: key
            ))
            try context.items.append(LegacyZoteroObjectFactory.attachmentObject(
                legacyKey: legacyKey,
                attachment: attachment,
                key: key,
                parentKey: LegacyZoteroObjectFactory.requiredItemKey(itemID, in: context.itemKeys)
            ))
            if let attachment {
                context.attachmentPaths.append((key, attachment.fileURL))
            }
        }
    }

    private static func projectAnnotations(in context: inout ProjectionContext) throws {
        for annotation in context.snapshot.annotations {
            let key = LegacyZoteroObjectFactory.annotationKey(for: annotation.id)
            try context.records.append(LegacyZoteroObjectFactory.record(
                entityKind: "annotation",
                legacyID: annotation.id.uuidString,
                value: annotation,
                objectKind: .item,
                objectKey: key
            ))
            let parentKey = context.attachmentKeys[annotation.attachmentKey]
                ?? LegacyZoteroObjectFactory.attachmentKey(for: annotation.attachmentKey)
            try context.items.append(LegacyZoteroObjectFactory.annotationObject(
                annotation,
                key: key,
                parentKey: parentKey
            ))
        }
    }

    private static func projectRelationships(in context: inout ProjectionContext) throws {
        for relationship in context.snapshot.relationships {
            let rawPayload = try LegacyZoteroObjectFactory.encode(relationship)
            context.records.append(LegacyMigrationObject(
                entityKind: "relationship",
                legacyID: relationship.id.uuidString,
                rawPayload: rawPayload,
                objectKind: nil,
                objectKey: nil
            ))
            try context.relationships.append(LegacyRelationshipProjection(
                relationship: relationship,
                sourceKey: LegacyZoteroObjectFactory.requiredItemKey(
                    relationship.sourceItemID,
                    in: context.itemKeys
                ),
                targetKey: LegacyZoteroObjectFactory.requiredItemKey(
                    relationship.targetItemID,
                    in: context.itemKeys
                ),
                rawPayload: rawPayload
            ))
        }
    }

    private static func projectReaderProgress(in context: inout ProjectionContext) throws {
        for progress in context.snapshot.readerProgress {
            let rawPayload = try LegacyZoteroObjectFactory.encode(progress)
            let key = context.attachmentKeys[progress.attachmentKey]
                ?? LegacyZoteroObjectFactory.attachmentKey(for: progress.attachmentKey)
            context.records.append(LegacyMigrationObject(
                entityKind: "readerProgress",
                legacyID: progress.attachmentKey,
                rawPayload: rawPayload,
                objectKind: nil,
                objectKey: key
            ))
            context.readerProgress.append(LegacyReaderProgressProjection(
                progress: progress,
                itemKey: key,
                rawPayload: rawPayload
            ))
        }
    }

    private static func validate(_ snapshot: LegacyLibrarySnapshot) throws {
        let itemIDs = Set(snapshot.items.map(\.id))
        let collectionIDs = Set(snapshot.collections.collections.map(\.id))
        for membership in snapshot.collections.memberships {
            guard itemIDs.contains(membership.itemID) else {
                throw LegacyLibraryMigrationError.missingItem(membership.itemID, entityKind: "membership")
            }
            guard collectionIDs.contains(membership.collectionID) else {
                throw LegacyLibraryMigrationError.missingCollection(membership.collectionID)
            }
        }
        try validateItemReferences(snapshot, itemIDs: itemIDs)
    }

    private static func validateItemReferences(_ snapshot: LegacyLibrarySnapshot, itemIDs: Set<UUID>) throws {
        for note in snapshot.notes where !itemIDs.contains(note.itemID) {
            throw LegacyLibraryMigrationError.missingItem(note.itemID, entityKind: "note")
        }
        for attachment in snapshot.attachments where !itemIDs.contains(attachment.itemID) {
            throw LegacyLibraryMigrationError.missingItem(attachment.itemID, entityKind: "attachment")
        }
        for annotation in snapshot.annotations where !itemIDs.contains(annotation.itemID) {
            throw LegacyLibraryMigrationError.missingItem(annotation.itemID, entityKind: "annotation")
        }
        for relationship in snapshot.relationships {
            guard itemIDs.contains(relationship.sourceItemID) else {
                throw LegacyLibraryMigrationError.missingItem(relationship.sourceItemID, entityKind: "relationship")
            }
            guard itemIDs.contains(relationship.targetItemID) else {
                throw LegacyLibraryMigrationError.missingItem(relationship.targetItemID, entityKind: "relationship")
            }
        }
        for progress in snapshot.readerProgress where !itemIDs.contains(progress.itemID) {
            throw LegacyLibraryMigrationError.missingItem(progress.itemID, entityKind: "readerProgress")
        }
    }
}

// MARK: - ProjectionContext

private struct ProjectionContext {
    // MARK: Lifecycle

    init(snapshot: LegacyLibrarySnapshot) {
        self.snapshot = snapshot
        itemKeys = Dictionary(uniqueKeysWithValues: snapshot.items.map {
            ($0.id, LegacyZoteroObjectFactory.itemKey(for: $0.id))
        })
        collectionKeys = Dictionary(uniqueKeysWithValues: snapshot.collections.collections.map {
            ($0.id, LegacyZoteroObjectFactory.collectionKey(for: $0.id))
        })
        memberships = Dictionary(grouping: snapshot.collections.memberships, by: \.itemID)
        let keys = Set(snapshot.attachments.map(\.attachmentKey))
            .union(snapshot.annotations.map(\.attachmentKey))
            .union(snapshot.readerProgress.map(\.attachmentKey))
        attachmentKeys = Dictionary(uniqueKeysWithValues: keys.map {
            ($0, LegacyZoteroObjectFactory.attachmentKey(for: $0))
        })
    }

    // MARK: Internal

    let snapshot: LegacyLibrarySnapshot
    let itemKeys: [UUID: String]
    let collectionKeys: [UUID: String]
    let memberships: [UUID: [LibraryCollectionMembership]]
    let attachmentKeys: [String: String]
    var collections: [ZoteroRawObject] = []
    var items: [ZoteroRawObject] = []
    var records: [LegacyMigrationObject] = []
    var relationships: [LegacyRelationshipProjection] = []
    var readerProgress: [LegacyReaderProgressProjection] = []
    var attachmentPaths: [(itemKey: String, fileURL: URL)] = []

    func itemID(forAttachmentKey key: String) -> UUID? {
        snapshot.attachments.first { $0.attachmentKey == key }?.itemID
            ?? snapshot.annotations.first { $0.attachmentKey == key }?.itemID
            ?? snapshot.readerProgress.first { $0.attachmentKey == key }?.itemID
    }
}
