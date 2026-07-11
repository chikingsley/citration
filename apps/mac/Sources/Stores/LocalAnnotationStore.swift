import CitrationCore
import Foundation

// MARK: - LocalAnnotationStorePaths

enum LocalAnnotationStorePaths {
    static func defaultStoreURL(
        appDirectoryName: String = "Citration",
        fileName: String = "annotations.json"
    ) throws -> URL {
        let appSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDirectory = appSupportDirectory.appendingPathComponent(appDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent(fileName)
    }
}

// MARK: - LocalAnnotationStore

actor LocalAnnotationStore: LibraryAnnotationStoring {
    // MARK: Lifecycle

    init(storeURL: URL, fileManager: FileManager = .default) throws {
        self.storeURL = storeURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()

        let directory = storeURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: storeURL.path) {
            try Data("[]".utf8).write(to: storeURL)
        }
    }

    // MARK: Internal

    func listAnnotations(itemID: UUID, attachmentKey: String? = nil) throws -> [LibraryAnnotation] {
        try loadAll()
            .filter { annotation in
                annotation.itemID == itemID &&
                    (attachmentKey == nil || annotation.attachmentKey == attachmentKey)
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func upsert(_ annotation: LibraryAnnotation) throws -> LibraryAnnotation {
        var annotations = try loadAll()
        var next = annotation
        next.updatedAt = .now

        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            next.createdAt = annotations[index].createdAt
            annotations[index] = next
        } else {
            annotations.append(next)
        }

        try saveAll(annotations)
        return next
    }

    func remove(id: UUID) throws {
        var annotations = try loadAll()
        annotations.removeAll { $0.id == id }
        try saveAll(annotations)
    }

    // MARK: Private

    private let storeURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private func loadAll() throws -> [LibraryAnnotation] {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return []
        }
        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([LibraryAnnotation].self, from: data)
    }

    private func saveAll(_ annotations: [LibraryAnnotation]) throws {
        let data = try encoder.encode(annotations)
        try data.write(to: storeURL, options: [.atomic])
    }
}
