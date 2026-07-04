import Foundation
import CitrationCore

extension AppModel {
    var allTags: [String] {
        BCItem.normalizedTags(items.flatMap(\.tags))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func addTagToSelectedItem() {
        guard let selectedItem else {
            statusMessage = "Select an item first"
            return
        }

        guard let tag = BCItem.normalizedTags([tagDraft]).first else {
            statusMessage = "Enter a tag first"
            return
        }

        var nextItem = selectedItem
        nextItem.tags = BCItem.normalizedTags(selectedItem.tags + [tag])
        tagDraft = ""

        guard nextItem.tags != selectedItem.tags else {
            statusMessage = "Tag already exists"
            return
        }

        persistItem(nextItem, status: "Added tag")
    }

    func removeTag(_ tag: String, from item: BCItem) {
        var nextItem = item
        nextItem.tags = item.tags.filter { existing in
            existing.localizedCaseInsensitiveCompare(tag) != .orderedSame
        }
        persistItem(nextItem, status: "Removed tag")
    }

    private func persistItem(_ item: BCItem, status: String) {
        let selectedID = item.id
        Task { @MainActor in
            await store.upsert(item)
            await refreshItems()
            selectedItemID = selectedID
            statusMessage = status
        }
    }
}
