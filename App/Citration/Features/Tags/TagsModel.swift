import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class TagsModel {
    // MARK: Internal

    var draft: String = ""

    var all: [String] {
        guard let context else {
            return []
        }
        return BCItem.normalizedTags(context.items.flatMap(\.tags))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func bind(context: any LibraryContext) {
        self.context = context
    }

    func addToSelectedItem() {
        guard let context, let selectedItem = context.selectedItem else {
            context?.statusMessage = "Select an item first"
            return
        }

        guard let tag = BCItem.normalizedTags([draft]).first else {
            context.statusMessage = "Enter a tag first"
            return
        }

        var nextItem = selectedItem
        nextItem.tags = BCItem.normalizedTags(selectedItem.tags + [tag])
        draft = ""

        guard nextItem.tags != selectedItem.tags else {
            context.statusMessage = "Tag already exists"
            return
        }

        context.persistItem(nextItem, status: "Added tag")
    }

    func remove(_ tag: String, from item: BCItem) {
        var nextItem = item
        nextItem.tags = item.tags.filter { existing in
            existing.localizedCaseInsensitiveCompare(tag) != .orderedSame
        }
        context?.persistItem(nextItem, status: "Removed tag")
    }

    // MARK: Private

    @ObservationIgnored private weak var context: (any LibraryContext)?
}
