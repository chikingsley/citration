import Foundation
import SwiftData
import BCCommon
import BCDomain

public enum BCDataLocalPaths {
    public static func defaultItemStoreURL(
        appDirectoryName: String = "BetterCite",
        fileName: String = "items.store"
    ) throws -> URL {
        let appSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let storeDirectory = appSupportDirectory.appendingPathComponent(appDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        return storeDirectory.appendingPathComponent(fileName)
    }
}

@Model
final class ItemRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var identifiersData: Data
    var itemTypeRawValue: String
    var creatorsData: Data
    var publicationYear: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        identifiersData: Data,
        itemTypeRawValue: String,
        creatorsData: Data,
        publicationYear: Int?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.identifiersData = identifiersData
        self.itemTypeRawValue = itemTypeRawValue
        self.creatorsData = creatorsData
        self.publicationYear = publicationYear
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public actor SwiftDataItemStore: BCItemStore {
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(storeURL: URL) throws {
        let schema = Schema([ItemRecord.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        self.container = try ModelContainer(for: schema, configurations: [configuration])
    }

    public func listItems() async -> [BCItem] {
        do {
            let context = ModelContext(container)
            let records = try context.fetch(FetchDescriptor<ItemRecord>())

            return try records
                .map(decodeItem)
                .sorted(by: sortItems)
        }
        catch {
            assertionFailure("SwiftDataItemStore.listItems failed: \(error)")
            return []
        }
    }

    public func upsert(_ item: BCItem) async {
        do {
            let context = ModelContext(container)
            let existingRecord = try fetchItemRecord(id: item.id, in: context)

            if let existingRecord {
                existingRecord.title = item.title
                existingRecord.identifiersData = try encoder.encode(item.identifiers)
                existingRecord.itemTypeRawValue = item.itemType.rawValue
                existingRecord.creatorsData = try encoder.encode(item.creators)
                existingRecord.publicationYear = item.publicationYear
                existingRecord.updatedAt = .now
            } else {
                let record = try encodeRecord(from: item)
                context.insert(record)
            }

            try context.save()
        }
        catch {
            assertionFailure("SwiftDataItemStore.upsert failed for item \(item.id): \(error)")
        }
    }

    public func removeItem(id: UUID) async {
        do {
            let context = ModelContext(container)
            if let record = try fetchItemRecord(id: id, in: context) {
                context.delete(record)
                try context.save()
            }
        }
        catch {
            assertionFailure("SwiftDataItemStore.removeItem failed for item \(id): \(error)")
        }
    }

    private func fetchItemRecord(id: UUID, in context: ModelContext) throws -> ItemRecord? {
        let descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { record in
            record.id == id
        })
        return try context.fetch(descriptor).first
    }

    private func encodeRecord(from item: BCItem) throws -> ItemRecord {
        try ItemRecord(
            id: item.id,
            title: item.title,
            identifiersData: encoder.encode(item.identifiers),
            itemTypeRawValue: item.itemType.rawValue,
            creatorsData: encoder.encode(item.creators),
            publicationYear: item.publicationYear,
            createdAt: item.createdAt,
            updatedAt: .now
        )
    }

    private func decodeItem(from record: ItemRecord) throws -> BCItem {
        let identifiers = try decoder.decode([Identifier].self, from: record.identifiersData)
        let creators = try decoder.decode([Creator].self, from: record.creatorsData)
        let itemType = ItemType(rawValue: record.itemTypeRawValue) ?? .unknown

        return BCItem(
            id: record.id,
            title: record.title,
            identifiers: identifiers,
            itemType: itemType,
            creators: creators,
            publicationYear: record.publicationYear,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private func sortItems(lhs: BCItem, rhs: BCItem) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}
