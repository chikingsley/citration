import CitrationCore
import Foundation

// MARK: - LibrarySource

enum LibrarySource: Hashable {
    case allItems
    case collection(UUID)
    case tag(String)
    case savedSearch(String)
    case trash
}

// MARK: - LibraryEmptyState

struct LibraryEmptyState {
    let title: String
    let systemImage: String
    let description: String
}

// MARK: - CollectionTreeNode

struct CollectionTreeNode: Identifiable {
    let collection: LibraryCollection
    let children: [CollectionTreeNode]?

    var id: UUID {
        collection.id
    }
}

extension [LibraryCollection] {
    func collectionTree() -> [CollectionTreeNode] {
        collectionChildren(parentID: nil, ancestors: [])
    }

    private func collectionChildren(parentID: UUID?, ancestors: Set<UUID>) -> [CollectionTreeNode] {
        filter { $0.parentID == parentID && !ancestors.contains($0.id) }
            .sorted { left, right in
                left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
            .map { collection in
                let descendants = collectionChildren(
                    parentID: collection.id,
                    ancestors: ancestors.union([collection.id])
                )
                return CollectionTreeNode(
                    collection: collection,
                    children: descendants.isEmpty ? nil : descendants
                )
            }
    }
}
