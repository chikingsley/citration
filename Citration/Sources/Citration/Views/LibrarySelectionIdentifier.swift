import CitrationCore
import Foundation

enum LibrarySelectionIdentifier {
    // MARK: Internal

    static let library = "library"

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
        guard
            let selection,
            selection.hasPrefix(collectionPrefix)
        else {
            return nil
        }

        return UUID(uuidString: String(selection.dropFirst(collectionPrefix.count)))
    }

    // MARK: Private

    private static let collectionPrefix = "collection:"
}
