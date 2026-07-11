import Foundation

extension IPadLibraryModel {
    func restoreScene(sourceToken: String, itemKey: String, attachmentKey: String) async {
        selectedSource = source(from: sourceToken)
        selectedItemIdentity = items.first { $0.identity.objectKey == itemKey }?.identity
        await refreshSelection()
        guard
            !attachmentKey.isEmpty,
            let item = selectedItem,
            let record = try? database.attachmentCacheRecord(
                libraryID: item.identity.libraryID,
                itemKey: attachmentKey
            ),
            let url = record.localURL,
            FileManager.default.fileExists(atPath: url.path)
        else {
            return
        }
        open(item: item, record: record, url: url)
    }

    func sceneToken(for source: Source?) -> String {
        switch source ?? .allItems {
        case .allItems:
            "all"
        case let .collection(id):
            "collection:\(id.uuidString)"
        case let .tag(tag):
            "tag:\(tag)"
        }
    }

    private func source(from token: String) -> Source {
        if token.hasPrefix("collection:"), let id = UUID(uuidString: String(token.dropFirst("collection:".count))) {
            return .collection(id)
        }
        if token.hasPrefix("tag:") {
            return .tag(String(token.dropFirst("tag:".count)))
        }
        return .allItems
    }
}
