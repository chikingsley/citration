import CitrationCore
import Foundation

// MARK: - LocalNoteStorePaths

enum LocalNoteStorePaths {
    static func defaultStoreURL(
        appDirectoryName: String = "Citration",
        fileName: String = "notes.json"
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

// MARK: - LocalNoteStore

actor LocalNoteStore: LibraryNoteStoring {
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

    func listNotes(itemID: UUID? = nil) throws -> [LibraryNote] {
        try loadAll()
            .filter { note in
                itemID == nil || note.itemID == itemID
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func upsert(_ note: LibraryNote) throws -> LibraryNote {
        var notes = try loadAll()
        var next = note
        next.text = next.text.trimmingCharacters(in: .whitespacesAndNewlines)
        next.updatedAt = .now

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            next.createdAt = notes[index].createdAt
            notes[index] = next
        } else {
            notes.append(next)
        }

        try saveAll(notes)
        return next
    }

    func remove(id: UUID) throws {
        var notes = try loadAll()
        notes.removeAll { $0.id == id }
        try saveAll(notes)
    }

    func removeNotes(itemIDs: [UUID]) throws {
        let idsToRemove = Set(itemIDs)
        guard !idsToRemove.isEmpty else {
            return
        }

        var notes = try loadAll()
        notes.removeAll { idsToRemove.contains($0.itemID) }
        try saveAll(notes)
    }

    // MARK: Private

    private let storeURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private func loadAll() throws -> [LibraryNote] {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return []
        }
        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([LibraryNote].self, from: data)
    }

    private func saveAll(_ notes: [LibraryNote]) throws {
        let data = try encoder.encode(notes)
        try data.write(to: storeURL, options: [.atomic])
    }
}
