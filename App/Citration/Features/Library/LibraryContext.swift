import CitrationCore
import Foundation

// MARK: - LibraryContext

/// The narrow slice of app-wide state that feature models may touch.
/// Feature models depend on this instead of the whole AppModel.
@MainActor
protocol LibraryContext: AnyObject {
    var statusMessage: String { get set }
    var selectedItemID: UUID? { get }
    var items: [BCItem] { get }
    var selectedItem: BCItem? { get }

    /// Persists an item edit, refreshes the library, and reports status.
    func persistItem(_ item: BCItem, status: String)
}

// MARK: - AppModel + LibraryContext

extension AppModel: LibraryContext {}
