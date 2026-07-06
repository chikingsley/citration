import CitrationCore
import Foundation

// MARK: - LocalCollectionStorePaths

enum LocalCollectionStorePaths {
    static func defaultStoreURL(
        appDirectoryName: String = "Citration",
        fileName: String = "collections.json"
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

// MARK: - LocalCollectionStore

actor LocalCollectionStore {
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
            let data = try encoder.encode(LibraryCollectionSnapshot())
            try data.write(to: storeURL, options: [.atomic])
        }
    }

    // MARK: Internal

    func snapshot() throws -> LibraryCollectionSnapshot {
        try loadSnapshot()
    }

    func createCollection(name: String, parentID: UUID? = nil) throws -> LibraryCollection {
        var snapshot = try loadSnapshot()
        let normalizedName = LibraryCollection.normalizedName(name) ?? "Untitled Collection"
        let collection = LibraryCollection(name: uniqueName(normalizedName, in: snapshot), parentID: parentID)
        snapshot.collections.append(collection)
        try saveSnapshot(snapshot)
        return collection
    }

    func removeCollection(id: UUID) throws {
        var snapshot = try loadSnapshot()
        let idsToRemove = descendantIDs(of: id, in: snapshot).union([id])
        snapshot.collections.removeAll { idsToRemove.contains($0.id) }
        snapshot.memberships.removeAll { idsToRemove.contains($0.collectionID) }
        try saveSnapshot(snapshot)
    }

    func addItem(_ itemID: UUID, to collectionID: UUID) throws -> LibraryCollectionMembership {
        var snapshot = try loadSnapshot()
        if
            let existing = snapshot.memberships.first(where: { membership in
                membership.collectionID == collectionID && membership.itemID == itemID
            })
        {
            return existing
        }

        let membership = LibraryCollectionMembership(collectionID: collectionID, itemID: itemID)
        snapshot.memberships.append(membership)
        try saveSnapshot(snapshot)
        return membership
    }

    func removeItem(_ itemID: UUID, from collectionID: UUID) throws {
        var snapshot = try loadSnapshot()
        snapshot.memberships.removeAll { membership in
            membership.collectionID == collectionID && membership.itemID == itemID
        }
        try saveSnapshot(snapshot)
    }

    func removeItems(ids itemIDs: [UUID]) throws {
        let idsToRemove = Set(itemIDs)
        guard !idsToRemove.isEmpty else {
            return
        }

        var snapshot = try loadSnapshot()
        snapshot.memberships.removeAll { idsToRemove.contains($0.itemID) }
        try saveSnapshot(snapshot)
    }

    // MARK: Private

    private let storeURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private func loadSnapshot() throws -> LibraryCollectionSnapshot {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return LibraryCollectionSnapshot()
        }
        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else {
            return LibraryCollectionSnapshot()
        }
        return try decoder.decode(LibraryCollectionSnapshot.self, from: data)
    }

    private func saveSnapshot(_ snapshot: LibraryCollectionSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: storeURL, options: [.atomic])
    }

    private func uniqueName(_ name: String, in snapshot: LibraryCollectionSnapshot) -> String {
        let existingNames = Set(snapshot.collections.map { $0.name.lowercased() })
        guard existingNames.contains(name.lowercased()) else {
            return name
        }

        var suffix = 2
        while existingNames.contains("\(name) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(name) \(suffix)"
    }

    private func descendantIDs(of collectionID: UUID, in snapshot: LibraryCollectionSnapshot) -> Set<UUID> {
        let children = snapshot.collections.filter { $0.parentID == collectionID }
        return children.reduce(into: Set<UUID>()) { result, collection in
            result.insert(collection.id)
            result.formUnion(descendantIDs(of: collection.id, in: snapshot))
        }
    }
}
