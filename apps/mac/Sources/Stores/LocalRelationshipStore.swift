import CitrationCore
import Foundation

// MARK: - LocalRelationshipStorePaths

enum LocalRelationshipStorePaths {
    static func defaultStoreURL(
        appDirectoryName: String = "Citration",
        fileName: String = "relationships.json"
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

// MARK: - LocalRelationshipStore

actor LocalRelationshipStore: LibraryRelationshipStoring {
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

    func listRelationships(itemID: UUID? = nil) throws -> [LibraryRelationship] {
        try loadAll()
            .filter { relationship in
                guard let itemID else {
                    return true
                }
                return relationship.sourceItemID == itemID || relationship.targetItemID == itemID
            }
            .sorted(by: sortRelationships)
    }

    func upsert(_ relationship: LibraryRelationship) throws -> LibraryRelationship {
        var relationships = try loadAll()
        var saved = LibraryRelationship(
            id: relationship.id,
            sourceItemID: relationship.sourceItemID,
            targetItemID: relationship.targetItemID,
            kind: relationship.kind,
            confidence: relationship.confidence,
            note: relationship.note
        )

        if let index = relationships.firstIndex(where: { $0.id == relationship.id }) {
            relationships[index] = saved
        } else if let index = relationships.firstIndex(where: { $0.hasSameLink(as: relationship) }) {
            saved.id = relationships[index].id
            relationships[index] = saved
        } else {
            relationships.append(saved)
        }

        try saveAll(relationships)
        return saved
    }

    func remove(id: UUID) throws {
        var relationships = try loadAll()
        relationships.removeAll { $0.id == id }
        try saveAll(relationships)
    }

    func removeRelationships(itemIDs: [UUID]) throws {
        let idsToRemove = Set(itemIDs)
        guard !idsToRemove.isEmpty else {
            return
        }

        var relationships = try loadAll()
        relationships.removeAll { relationship in
            idsToRemove.contains(relationship.sourceItemID) || idsToRemove.contains(relationship.targetItemID)
        }
        try saveAll(relationships)
    }

    // MARK: Private

    private let storeURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private func loadAll() throws -> [LibraryRelationship] {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return []
        }
        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([LibraryRelationship].self, from: data)
    }

    private func saveAll(_ relationships: [LibraryRelationship]) throws {
        let data = try encoder.encode(relationships)
        try data.write(to: storeURL, options: [.atomic])
    }

    private func sortRelationships(_ lhs: LibraryRelationship, _ rhs: LibraryRelationship) -> Bool {
        if lhs.kind.rawValue == rhs.kind.rawValue {
            if lhs.sourceItemID == rhs.sourceItemID {
                return lhs.targetItemID.uuidString < rhs.targetItemID.uuidString
            }
            return lhs.sourceItemID.uuidString < rhs.sourceItemID.uuidString
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}

private extension LibraryRelationship {
    func hasSameLink(as other: LibraryRelationship) -> Bool {
        sourceItemID == other.sourceItemID &&
            targetItemID == other.targetItemID &&
            kind == other.kind
    }
}
