import Foundation
import GRDB

extension CitrationLibraryStore {
    public func importFile(from sourceURL: URL, for item: BCItem) throws -> LibraryAttachment {
        guard sourceURL.isFileURL, fileManager.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard let parentKey = try objectKey(for: item.id, kind: .item) else {
            throw CitrationDatabaseError.invalidObjectKey
        }
        let destinationDirectory = attachmentsDirectory
            .appending(path: "\(item.id.uuidString)--\(slug(item.title))", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: sourceURL, in: destinationDirectory)
        try fileManager.copyItem(at: sourceURL, to: destination)

        let values = try destination.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        let createdAt = values.creationDate ?? .now
        let legacyKey = "\(item.id.uuidString)/\(destination.lastPathComponent)"
        let key = LegacyZoteroObjectFactory.attachmentKey(for: legacyKey)
        let attachment = LegacyAttachmentRecord(
            itemID: item.id,
            attachmentKey: legacyKey,
            fileURL: destination,
            contentType: contentType(for: destination),
            size: Int64(values.fileSize ?? 0),
            createdAt: createdAt
        )
        let object = try LegacyZoteroObjectFactory.attachmentObject(
            legacyKey: legacyKey,
            attachment: attachment,
            key: key,
            parentKey: parentKey
        )
        try database.storeLocalItems([object], libraryID: libraryID)
        try upsertIdentity(
            uuid: UUID(),
            kind: .item,
            key: key,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        try markAttachmentDownloaded(key: key, path: destination.path)
        return libraryAttachment(record: attachment, objectKey: key)
    }

    public func listAttachments(for itemID: UUID) throws -> [LibraryAttachment] {
        guard let parentKey = try objectKey(for: itemID, kind: .item) else {
            return []
        }
        return try database.databaseQueue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT item_key, filename, content_type, local_path, downloaded_at
                FROM attachment_projections
                WHERE library_id = ? AND parent_item_key = ?
                  AND cache_state = 'downloaded' AND local_path IS NOT NULL
                ORDER BY filename COLLATE NOCASE
                """,
                arguments: [libraryID, parentKey]
            ).compactMap { row in
                let path: String = row["local_path"]
                let url = URL(filePath: path)
                guard self.fileManager.fileExists(atPath: path) else {
                    return nil
                }
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                return LibraryAttachment(
                    itemID: itemID,
                    fileName: row["filename"],
                    objectKey: row["item_key"],
                    localURL: url,
                    contentType: row["content_type"],
                    size: Int64(values.fileSize ?? 0),
                    createdAt: values.creationDate ?? .distantPast
                )
            }
        }
    }

    public func removeAttachment(_ attachment: LibraryAttachment) throws {
        if fileManager.fileExists(atPath: attachment.localURL.path) {
            try fileManager.removeItem(at: attachment.localURL)
        }
        try markDeleted(kind: .item, key: attachment.objectKey)
    }

    private func markAttachmentDownloaded(key: String, path: String) throws {
        try database.databaseQueue.write { database in
            try database.execute(
                sql: """
                UPDATE attachment_projections
                SET cache_state = 'downloaded', local_path = ?, downloaded_at = ?
                WHERE library_id = ? AND item_key = ?
                """,
                arguments: [path, Date().timeIntervalSince1970, libraryID, key]
            )
        }
    }

    private func uniqueDestination(for source: URL, in directory: URL) -> URL {
        let extensionPart = source.pathExtension
        let stem = slug(source.deletingPathExtension().lastPathComponent)
        var candidate = directory.appending(path: fileName(stem: stem, extensionPart: extensionPart))
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: fileName(stem: "\(stem)-\(index)", extensionPart: extensionPart))
            index += 1
        }
        return candidate
    }

    private func fileName(stem: String, extensionPart: String) -> String {
        extensionPart.isEmpty ? stem : "\(stem).\(extensionPart.lowercased())"
    }

    private func slug(_ value: String) -> String {
        let normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-zA-Z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "attachment" : String(normalized.prefix(96))
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": "application/pdf"
        case "epub": "application/epub+zip"
        case "html",
             "htm": "text/html"
        case "txt",
             "md": "text/plain"
        case "png": "image/png"
        case "jpg",
             "jpeg": "image/jpeg"
        default: "application/octet-stream"
        }
    }

    private func libraryAttachment(
        record: LegacyAttachmentRecord,
        objectKey: String
    ) -> LibraryAttachment {
        LibraryAttachment(
            itemID: record.itemID,
            fileName: record.fileURL.lastPathComponent,
            objectKey: objectKey,
            localURL: record.fileURL,
            contentType: record.contentType,
            size: record.size,
            createdAt: record.createdAt
        )
    }
}
