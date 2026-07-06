import Foundation

// MARK: - BCItemStore

public protocol BCItemStore: Sendable {
    func listItems() async -> [BCItem]
    func upsert(_ item: BCItem) async
    func removeItem(id: UUID) async
}

// MARK: - InMemoryItemStore

public actor InMemoryItemStore: BCItemStore {
    // MARK: Lifecycle

    public init(initialItems: [BCItem] = []) {
        itemsByID = Dictionary(uniqueKeysWithValues: initialItems.map { ($0.id, $0) })
    }

    // MARK: Public

    public func listItems() -> [BCItem] {
        itemsByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func upsert(_ item: BCItem) {
        var next = item
        next.updatedAt = .now
        if let existing = itemsByID[item.id] {
            next.createdAt = existing.createdAt
        }
        itemsByID[next.id] = next
    }

    public func removeItem(id: UUID) {
        itemsByID[id] = nil
    }

    // MARK: Private

    private var itemsByID: [UUID: BCItem]
}
