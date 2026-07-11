import Foundation

// MARK: - BCItemStore

public protocol BCItemStore: Sendable {
    func listItems() async -> [BCItem]
    func upsert(_ item: BCItem) async
    func removeItem(id: UUID) async
}
