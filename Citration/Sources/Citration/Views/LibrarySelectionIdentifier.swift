import Foundation
import CitrationCore

enum LibrarySelectionIdentifier {
    static let library = "library"
    private static let collectionPrefix = "collection:"

    static func value(for collection: LibraryCollection) -> String {
        value(for: collection.id)
    }

    static func value(for collectionID: UUID?) -> String {
        guard let collectionID else {
            return library
        }
        return "\(collectionPrefix)\(collectionID.uuidString)"
    }

    static func collectionID(from selection: String?) -> UUID? {
        guard let selection,
              selection.hasPrefix(collectionPrefix) else {
            return nil
        }

        return UUID(uuidString: String(selection.dropFirst(collectionPrefix.count)))
    }
}
