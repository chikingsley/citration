import CryptoKit
import Foundation
import GRDB

// MARK: - LegacyAttachmentRecord

public struct LegacyAttachmentRecord: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        itemID: UUID,
        attachmentKey: String,
        fileURL: URL,
        contentType: String,
        size: Int64,
        createdAt: Date
    ) {
        self.itemID = itemID
        self.attachmentKey = attachmentKey
        self.fileURL = fileURL
        self.contentType = contentType
        self.size = size
        self.createdAt = createdAt
    }

    // MARK: Public

    public let itemID: UUID
    public let attachmentKey: String
    public let fileURL: URL
    public let contentType: String
    public let size: Int64
    public let createdAt: Date
}

// MARK: - LegacyLibrarySnapshot

public struct LegacyLibrarySnapshot: Sendable {
    // MARK: Lifecycle

    public init(
        items: [BCItem],
        collections: LibraryCollectionSnapshot,
        notes: [LibraryNote],
        attachments: [LegacyAttachmentRecord],
        annotations: [LibraryAnnotation],
        relationships: [LibraryRelationship],
        readerProgress: [ReaderProgress]
    ) {
        self.items = items
        self.collections = collections
        self.notes = notes
        self.attachments = attachments
        self.annotations = annotations
        self.relationships = relationships
        self.readerProgress = readerProgress
    }

    // MARK: Public

    public let items: [BCItem]
    public let collections: LibraryCollectionSnapshot
    public let notes: [LibraryNote]
    public let attachments: [LegacyAttachmentRecord]
    public let annotations: [LibraryAnnotation]
    public let relationships: [LibraryRelationship]
    public let readerProgress: [ReaderProgress]
}

// MARK: - LegacyLibrarySources

public struct LegacyLibrarySources: Sendable {
    // MARK: Lifecycle

    public init(applicationDirectory: URL) {
        self.applicationDirectory = applicationDirectory
        itemStoreURL = applicationDirectory.appending(path: "items.store")
        collectionsURL = applicationDirectory.appending(path: "collections.json")
        notesURL = applicationDirectory.appending(path: "notes.json")
        annotationsURL = applicationDirectory.appending(path: "annotations.json")
        relationshipsURL = applicationDirectory.appending(path: "relationships.json")
        readerProgressURL = applicationDirectory.appending(path: "reader-progress.json")
        attachmentsDirectory = applicationDirectory.appending(path: "attachments", directoryHint: .isDirectory)
    }

    // MARK: Public

    public let applicationDirectory: URL
    public let itemStoreURL: URL
    public let collectionsURL: URL
    public let notesURL: URL
    public let annotationsURL: URL
    public let relationshipsURL: URL
    public let readerProgressURL: URL
    public let attachmentsDirectory: URL

    public func fingerprint(fileManager: FileManager = .default) throws -> String {
        var hasher = SHA256()
        if fileManager.fileExists(atPath: itemStoreURL.path) {
            try updateItemStoreFingerprint(&hasher)
        }
        for url in metadataURLs.sorted(by: { $0.path < $1.path }) where fileManager.fileExists(atPath: url.path) {
            hasher.update(data: Data(url.lastPathComponent.utf8))
            try hasher.update(data: Data(contentsOf: url))
        }
        for url in try attachmentFiles(fileManager: fileManager) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let relativePath = String(url.path.dropFirst(attachmentsDirectory.path.count))
            let metadata = "\(relativePath)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            hasher.update(data: Data(metadata.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func backup(to rootDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        let fingerprint = try fingerprint(fileManager: fileManager)
        let backupDirectory = rootDirectory
            .appending(path: "legacy-\(fingerprint.prefix(16))", directoryHint: .isDirectory)
        let completionMarker = backupDirectory.appending(path: "backup-complete.json")
        if fileManager.fileExists(atPath: completionMarker.path) {
            return backupDirectory
        }

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: backupDirectory.path) {
            try fileManager.removeItem(at: backupDirectory)
        }
        let stagingDirectory = rootDirectory
            .appending(path: ".legacy-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        if fileManager.fileExists(atPath: itemStoreURL.path) {
            var configuration = Configuration()
            configuration.readonly = true
            let source = try DatabaseQueue(path: itemStoreURL.path, configuration: configuration)
            let destination = try DatabaseQueue(path: stagingDirectory.appending(path: "items.store").path)
            try source.backup(to: destination)
        }

        for sourceURL in jsonURLs where fileManager.fileExists(atPath: sourceURL.path) {
            try fileManager.copyItem(
                at: sourceURL,
                to: stagingDirectory.appending(path: sourceURL.lastPathComponent)
            )
        }
        if fileManager.fileExists(atPath: attachmentsDirectory.path) {
            try fileManager.copyItem(
                at: attachmentsDirectory,
                to: stagingDirectory.appending(path: "attachments", directoryHint: .isDirectory)
            )
        }
        let marker = try JSONEncoder().encode(LegacyBackupMarker(sourceFingerprint: fingerprint))
        try marker.write(to: stagingDirectory.appending(path: completionMarker.lastPathComponent), options: .atomic)
        try fileManager.moveItem(at: stagingDirectory, to: backupDirectory)
        return backupDirectory
    }

    public func load(fileManager: FileManager = .default) throws -> LegacyLibrarySnapshot {
        let items: [BCItem] = if fileManager.fileExists(atPath: itemStoreURL.path) {
            try SwiftDataItemStore.exportItemsSynchronously(storeURL: itemStoreURL)
        } else {
            []
        }

        return try LegacyLibrarySnapshot(
            items: items,
            collections: decode(
                LibraryCollectionSnapshot.self,
                from: collectionsURL,
                default: .init(),
                fileManager: fileManager
            ),
            notes: decode([LibraryNote].self, from: notesURL, default: [], fileManager: fileManager),
            attachments: attachmentRecords(fileManager: fileManager),
            annotations: decode([LibraryAnnotation].self, from: annotationsURL, default: [], fileManager: fileManager),
            relationships: decode(
                [LibraryRelationship].self,
                from: relationshipsURL,
                default: [],
                fileManager: fileManager
            ),
            readerProgress: decode(
                [ReaderProgress].self,
                from: readerProgressURL,
                default: [],
                fileManager: fileManager
            )
        )
    }

    // MARK: Private

    private var jsonURLs: [URL] {
        [collectionsURL, notesURL, annotationsURL, relationshipsURL, readerProgressURL]
    }

    private var metadataURLs: [URL] {
        jsonURLs
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": "application/pdf"
        case "epub": "application/epub+zip"
        case "html",
             "htm": "text/html"
        case "txt",
             "md": "text/plain"
        default: "application/octet-stream"
        }
    }

    private func updateItemStoreFingerprint(_ hasher: inout SHA256) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: itemStoreURL.path, configuration: configuration)
        let canonicalRows = try queue.read { database -> [String] in
            let tableExists = try Bool.fetchOne(
                database,
                sql: "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = 'ZITEMRECORD')"
            ) ?? false
            guard tableExists else {
                return []
            }
            let columns = try Row.fetchAll(database, sql: "PRAGMA table_info(ZITEMRECORD)").map { row in
                let name: String = row["name"]
                return "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            guard !columns.isEmpty else {
                return []
            }
            let expression = columns.map { "quote(\($0))" }.joined(separator: " || char(31) || ")
            return try String.fetchAll(
                database,
                sql: "SELECT \(expression) FROM ZITEMRECORD ORDER BY Z_PK"
            )
        }
        hasher.update(data: Data("items.store/ZITEMRECORD".utf8))
        for row in canonicalRows {
            hasher.update(data: Data(row.utf8))
            hasher.update(data: Data([0]))
        }
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from url: URL,
        default value: Value,
        fileManager: FileManager
    ) throws -> Value {
        guard fileManager.fileExists(atPath: url.path) else {
            return value
        }
        let data = try Data(contentsOf: url)
        return data.isEmpty ? value : try JSONDecoder().decode(type, from: data)
    }

    private func attachmentFiles(fileManager: FileManager) throws -> [URL] {
        guard
            fileManager.fileExists(atPath: attachmentsDirectory.path),
            let enumerator = fileManager.enumerator(
                at: attachmentsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        return try enumerator.compactMap { element -> URL? in
            guard let url = element as? URL else {
                return nil
            }
            return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true ? url : nil
        }.sorted { $0.path < $1.path }
    }

    private func attachmentRecords(fileManager: FileManager) throws -> [LegacyAttachmentRecord] {
        try attachmentFiles(fileManager: fileManager).compactMap { url in
            let directoryName = url.deletingLastPathComponent().lastPathComponent
            let uuidText = directoryName.split(separator: "--", maxSplits: 1).first.map(String.init) ?? directoryName
            guard let itemID = UUID(uuidString: uuidText) else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            return LegacyAttachmentRecord(
                itemID: itemID,
                attachmentKey: "\(itemID.uuidString)/\(url.lastPathComponent)",
                fileURL: url,
                contentType: Self.contentType(for: url),
                size: Int64(values.fileSize ?? 0),
                createdAt: values.creationDate ?? .distantPast
            )
        }
    }
}

// MARK: - LegacyBackupMarker

private struct LegacyBackupMarker: Codable {
    let sourceFingerprint: String
}
