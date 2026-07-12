import CitrationCore
import Foundation

extension IPadLibraryModel {
    var availableTags: [String] {
        Set(items.flatMap(\.tags)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var visibleItems: [SynchronizedLibraryItem] {
        let sourceItems = switch selectedSource ?? .allItems {
        case .allItems:
            items
        case let .collection(collectionID):
            collectionItems(collectionID: collectionID)
        case let .tag(tag):
            items.filter { item in
                item.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return sourceItems
        }
        return sourceItems.filter { searchResultKeys.contains($0.identity.objectKey) }
    }

    var selectedSourceTitle: String {
        switch selectedSource ?? .allItems {
        case .allItems:
            "All Items"
        case let .collection(collectionID):
            collections.collections.first(where: { $0.id == collectionID })?.name ?? "Collection"
        case let .tag(tag):
            tag
        }
    }

    var accountDisplayName: String {
        switch configuration {
        case .localOnly:
            "Local Library"
        case let .connected(profile):
            profile.displayName
        }
    }

    var accountInitials: String {
        let words = accountDisplayName.split(whereSeparator: { $0.isWhitespace })
        let initials = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? "C" : initials.uppercased()
    }

    private func collectionItems(collectionID: UUID) -> [SynchronizedLibraryItem] {
        let itemIDs = Set(
            collections.memberships
                .filter { $0.collectionID == collectionID }
                .map(\.itemID)
        )
        return items.filter { itemIDs.contains($0.identity.appUUID) }
    }
}
