import Foundation

enum LibraryItemDragPayload {
    // MARK: Internal

    static func encode(_ ids: [UUID]) -> String {
        let values = Set(ids).map(\.uuidString).sorted()
        return prefix + values.joined(separator: ",")
    }

    static func decode(_ value: String) -> [UUID]? {
        guard value.hasPrefix(prefix) else {
            return nil
        }
        let encoded = value.dropFirst(prefix.count)
        let ids = encoded.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        return ids.isEmpty ? nil : ids
    }

    // MARK: Private

    private static let prefix = "citration-library-items:"
}
