import CitrationCore
import Foundation

extension AppModel {
    var selectedCollectionItems: [BCItem] {
        guard let selectedCollectionID else {
            return items
        }

        let itemIDs = Set(
            collectionMemberships
                .filter { $0.collectionID == selectedCollectionID }
                .map(\.itemID)
        )
        return items.filter { itemIDs.contains($0.id) }
    }

    func refreshCollections() async {
        do {
            let snapshot = try await collectionStore.snapshot()
            collections = snapshot.collections.sorted(by: sortCollections)
            collectionMemberships = snapshot.memberships

            if
                let selectedCollectionID,
                !collections.contains(where: { $0.id == selectedCollectionID })
            {
                self.selectedCollectionID = nil
            }

            await refreshSelectedItemCollections()
        } catch {
            collections = []
            collectionMemberships = []
            selectedCollectionID = nil
            selectedItemCollectionIDs = []
            statusMessage = "Failed to load collections"
        }
    }

    func selectCollection(id: UUID?) {
        selectedCollectionID = id
    }

    func createCollection(named name: String = "New Collection") {
        Task {
            do {
                let collection = try await collectionStore.createCollection(name: name)
                await refreshCollections()
                selectedCollectionID = collection.id
                statusMessage = "Created collection"
            } catch {
                statusMessage = "Failed to create collection"
            }
        }
    }

    func removeCollection(_ collection: LibraryCollection) {
        Task {
            do {
                try await collectionStore.removeCollection(id: collection.id)
                await refreshCollections()
                statusMessage = "Removed collection"
            } catch {
                statusMessage = "Failed to remove collection"
            }
        }
    }

    func setSelectedItem(_ item: BCItem, memberOf collection: LibraryCollection, isMember: Bool) {
        Task {
            do {
                if isMember {
                    _ = try await collectionStore.addItem(item.id, to: collection.id)
                } else {
                    try await collectionStore.removeItem(item.id, from: collection.id)
                }
                await refreshCollections()
                statusMessage = isMember ? "Added to collection" : "Removed from collection"
            } catch {
                statusMessage = "Failed to update collection"
            }
        }
    }

    func refreshSelectedItemCollections() {
        guard let selectedItemID else {
            selectedItemCollectionIDs = []
            return
        }

        selectedItemCollectionIDs = Set(
            collectionMemberships
                .filter { $0.itemID == selectedItemID }
                .map(\.collectionID)
        )
    }

    func addItemToSelectedCollectionIfNeeded(_ itemID: UUID) async {
        guard let selectedCollectionID else {
            return
        }

        do {
            _ = try await collectionStore.addItem(itemID, to: selectedCollectionID)
            await refreshCollections()
        } catch {
            statusMessage = "Imported, but failed to file in collection"
        }
    }

    private func sortCollections(_ lhs: LibraryCollection, _ rhs: LibraryCollection) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
