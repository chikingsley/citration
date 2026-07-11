import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class CollectionsModel {
    // MARK: Lifecycle

    init(store: any LibraryCollectionStoring) {
        self.store = store
    }

    // MARK: Internal

    var all: [LibraryCollection] = []
    var memberships: [LibraryCollectionMembership] = []
    var selectedID: UUID?
    var selectedItemCollectionIDs: Set<UUID> = []

    let store: any LibraryCollectionStoring

    /// Items in the selected collection; the whole library when none is selected.
    var selectedCollectionItems: [BCItem] {
        guard let context else {
            return []
        }
        guard let selectedID else {
            return context.items
        }

        let itemIDs = Set(
            memberships
                .filter { $0.collectionID == selectedID }
                .map(\.itemID)
        )
        return context.items.filter { itemIDs.contains($0.id) }
    }

    func bind(context: any LibraryContext) {
        self.context = context
    }

    func refresh() async {
        do {
            let snapshot = try await store.snapshot()
            all = snapshot.collections.sorted(by: sortCollections)
            memberships = snapshot.memberships

            if
                let selectedID,
                !all.contains(where: { $0.id == selectedID })
            {
                self.selectedID = nil
            }

            refreshSelectedItemMemberships()
        } catch {
            all = []
            memberships = []
            selectedID = nil
            selectedItemCollectionIDs = []
            context?.statusMessage = "Failed to load collections"
        }
    }

    func select(id: UUID?) {
        selectedID = id
    }

    func create(named name: String = "New Collection") {
        Task {
            do {
                let collection = try await store.createCollection(name: name)
                await refresh()
                selectedID = collection.id
                context?.statusMessage = "Created collection"
            } catch {
                context?.statusMessage = "Failed to create collection"
            }
        }
    }

    func remove(_ collection: LibraryCollection) {
        Task {
            do {
                try await store.removeCollection(id: collection.id)
                await refresh()
                context?.statusMessage = "Removed collection"
            } catch {
                context?.statusMessage = "Failed to remove collection"
            }
        }
    }

    func set(_ item: BCItem, memberOf collection: LibraryCollection, isMember: Bool) {
        Task {
            do {
                if isMember {
                    _ = try await store.addItem(item.id, to: collection.id)
                } else {
                    try await store.removeItem(item.id, from: collection.id)
                }
                await refresh()
                context?.statusMessage = isMember ? "Added to collection" : "Removed from collection"
            } catch {
                context?.statusMessage = "Failed to update collection"
            }
        }
    }

    /// Recomputes which collections the selected item belongs to.
    func refreshSelectedItemMemberships() {
        guard let selectedItemID = context?.selectedItemID else {
            selectedItemCollectionIDs = []
            return
        }

        selectedItemCollectionIDs = Set(
            memberships
                .filter { $0.itemID == selectedItemID }
                .map(\.collectionID)
        )
    }

    /// Files a newly imported item into the selected collection, if any.
    func fileInSelectedCollection(_ itemID: UUID) async {
        guard let selectedID else {
            return
        }

        do {
            _ = try await store.addItem(itemID, to: selectedID)
            await refresh()
        } catch {
            context?.statusMessage = "Imported, but failed to file in collection"
        }
    }

    /// Cascade cleanup when items are removed from the library.
    func removeItems(ids: [UUID]) async {
        try? await store.removeItems(ids: ids)
        await refresh()
    }

    // MARK: Private

    @ObservationIgnored private weak var context: (any LibraryContext)?

    private func sortCollections(_ lhs: LibraryCollection, _ rhs: LibraryCollection) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
