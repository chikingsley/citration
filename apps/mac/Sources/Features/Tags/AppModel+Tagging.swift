import CitrationCore
import Foundation

extension AppModel {
    func addTag(_ tag: String, toItemIDs ids: [UUID]) {
        guard let normalizedTag = BCItem.normalizedTags([tag]).first else {
            return
        }
        let uniqueIDs = Set(ids)
        let targets = items.filter { uniqueIDs.contains($0.identity.appUUID) }
        guard !targets.isEmpty else {
            return
        }
        Task { @MainActor in
            for target in targets {
                var item = target.bibliographic
                item.tags = BCItem.normalizedTags(item.tags + [normalizedTag])
                await store.upsert(item)
            }
            await refreshItems()
            statusMessage = targets.count == 1
                ? "Added tag \(normalizedTag)"
                : "Added \(normalizedTag) to \(targets.count) items"
        }
    }

    func removeTagFromLibrary(_ tag: String) {
        let targets = items.filter { item in
            item.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
        }
        guard !targets.isEmpty else {
            return
        }
        Task { @MainActor in
            for target in targets {
                var item = target.bibliographic
                item.tags.removeAll { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
                await store.upsert(item)
            }
            await refreshItems()
            statusMessage = "Removed tag \(tag) from \(targets.count) items"
        }
    }
}
