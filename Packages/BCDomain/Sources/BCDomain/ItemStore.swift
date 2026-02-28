import Foundation

public protocol BCItemStore: Sendable {
    func listItems() async -> [BCItem]
    func upsert(_ item: BCItem) async
    func removeItem(id: UUID) async
}

public actor InMemoryItemStore: BCItemStore {
    private var itemsByID: [UUID: BCItem]

    public init(initialItems: [BCItem] = []) {
        self.itemsByID = Dictionary(uniqueKeysWithValues: initialItems.map { ($0.id, $0) })
    }

    public func listItems() async -> [BCItem] {
        itemsByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func upsert(_ item: BCItem) async {
        var next = item
        next.updatedAt = .now
        if let existing = itemsByID[item.id] {
            next.createdAt = existing.createdAt
        }
        itemsByID[next.id] = next
    }

    public func removeItem(id: UUID) async {
        itemsByID[id] = nil
    }
}
