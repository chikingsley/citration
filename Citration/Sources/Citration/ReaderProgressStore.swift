import Foundation
import CitrationCore

enum LocalReaderProgressStorePaths {
    static func defaultStoreURL(
        appDirectoryName: String = "Citration",
        fileName: String = "reader-progress.json"
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

actor LocalReaderProgressStore {
    private let storeURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(storeURL: URL, fileManager: FileManager = .default) throws {
        self.storeURL = storeURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()

        let directory = storeURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: storeURL.path) {
            try Data("[]".utf8).write(to: storeURL)
        }
    }

    func progress(for attachmentKey: String) throws -> ReaderProgress? {
        try loadAll().first { $0.attachmentKey == attachmentKey }
    }

    func listProgress(itemID: UUID? = nil) throws -> [ReaderProgress] {
        try loadAll()
            .filter { progress in
                itemID == nil || progress.itemID == itemID
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.attachmentKey < rhs.attachmentKey
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func upsert(_ progress: ReaderProgress) throws -> ReaderProgress {
        var allProgress = try loadAll()
        var next = progress
        next.updatedAt = .now

        if let index = allProgress.firstIndex(where: { $0.attachmentKey == progress.attachmentKey }) {
            allProgress[index] = next
        } else {
            allProgress.append(next)
        }

        try saveAll(allProgress)
        return next
    }

    func remove(attachmentKey: String) throws {
        var allProgress = try loadAll()
        allProgress.removeAll { $0.attachmentKey == attachmentKey }
        try saveAll(allProgress)
    }

    func removeProgress(itemIDs: [UUID]) throws {
        let idsToRemove = Set(itemIDs)
        guard !idsToRemove.isEmpty else { return }

        var allProgress = try loadAll()
        allProgress.removeAll { idsToRemove.contains($0.itemID) }
        try saveAll(allProgress)
    }

    private func loadAll() throws -> [ReaderProgress] {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return []
        }
        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([ReaderProgress].self, from: data)
    }

    private func saveAll(_ progress: [ReaderProgress]) throws {
        let data = try encoder.encode(progress)
        try data.write(to: storeURL, options: [.atomic])
    }
}
