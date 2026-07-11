import Foundation
import SwiftData

// MARK: - ItemRecord

@Model
final class ItemRecord {
    // MARK: Lifecycle

    init(
        id: UUID,
        title: String,
        identifiersData: Data,
        itemTypeRawValue: String,
        creatorsData: Data,
        publicationYear: Int?,
        tagsData: Data? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.identifiersData = identifiersData
        self.itemTypeRawValue = itemTypeRawValue
        self.creatorsData = creatorsData
        self.publicationYear = publicationYear
        self.tagsData = tagsData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: Internal

    @Attribute(.unique) var id: UUID
    var title: String
    var identifiersData: Data
    var itemTypeRawValue: String
    var creatorsData: Data
    var publicationYear: Int?
    var tagsData: Data?
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - SwiftDataItemStore

public actor SwiftDataItemStore: BCItemStore {
    // MARK: Lifecycle

    public init(storeURL: URL) throws {
        let schema = Schema([ItemRecord.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: Public

    public func listItems() -> [BCItem] {
        do {
            return try exportItems()
        } catch {
            assertionFailure("SwiftDataItemStore.listItems failed: \(error)")
            return []
        }
    }

    public func exportItems() throws -> [BCItem] {
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<ItemRecord>())
        return try records
            .map(decodeItem)
            .sorted(by: sortItems)
    }

    public func upsert(_ item: BCItem) {
        do {
            let context = ModelContext(container)
            let existingRecord = try fetchItemRecord(id: item.id, in: context)

            if let existingRecord {
                existingRecord.title = item.title
                existingRecord.identifiersData = try encoder.encode(item.identifiers)
                existingRecord.itemTypeRawValue = item.itemType.rawValue
                existingRecord.creatorsData = try encoder.encode(item.creators)
                existingRecord.publicationYear = item.publicationYear
                existingRecord.tagsData = try encoder.encode(item.tags)
                existingRecord.updatedAt = .now
            } else {
                let record = try encodeRecord(from: item)
                context.insert(record)
            }

            try context.save()
        } catch {
            assertionFailure("SwiftDataItemStore.upsert failed for item \(item.id): \(error)")
        }
    }

    public func removeItem(id: UUID) {
        do {
            let context = ModelContext(container)
            if let record = try fetchItemRecord(id: id, in: context) {
                context.delete(record)
                try context.save()
            }
        } catch {
            assertionFailure("SwiftDataItemStore.removeItem failed for item \(id): \(error)")
        }
    }

    // MARK: Private

    private let container: ModelContainer
    private let encoder: JSONEncoder = .init()
    private let decoder: JSONDecoder = .init()

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
            tagsData: encoder.encode(item.tags),
            createdAt: item.createdAt,
            updatedAt: .now
        )
    }

    private func decodeItem(from record: ItemRecord) throws -> BCItem {
        let identifiers = try decoder.decode([Identifier].self, from: record.identifiersData)
        let creators = try decoder.decode([Creator].self, from: record.creatorsData)
        let tags = try record.tagsData.map { try decoder.decode([String].self, from: $0) } ?? []
        let itemType = ItemType(rawValue: record.itemTypeRawValue) ?? .unknown

        return BCItem(
            id: record.id,
            title: record.title,
            identifiers: identifiers,
            itemType: itemType,
            creators: creators,
            publicationYear: record.publicationYear,
            tags: tags,
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
