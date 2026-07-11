import CitrationCore
import Foundation

// MARK: - LibraryContext

/// The narrow slice of app-wide state that feature models may touch.
/// Feature models depend on this instead of the whole AppModel.
@MainActor
protocol LibraryContext: AnyObject {
    var statusMessage: String { get set }
    var selectedItemID: UUID? { get set }
    var items: [SynchronizedLibraryItem] { get }
    var bibliographicItems: [BCItem] { get }
    var selectedItem: BCItem? { get }

    /// Persists an item edit, refreshes the library, and reports status.
    func persistItem(_ item: BCItem, status: String)

    /// Adds a new item to the library and refreshes it.
    func addItem(_ item: BCItem) async

    /// Full selection change with per-feature cleanup side effects.
    func selectItem(id: UUID?)

    /// Reloads items and per-selection state across features.
    func refreshLibrary() async

    /// Reconciles an attachment mutation with every open document session.
    func handleAttachmentRemoved(_ attachment: LocalAttachment) async
    func reconcileOpenDocuments(itemID: UUID, availableAttachments: [LocalAttachment])
}

// MARK: - AppModel + LibraryContext

extension AppModel: LibraryContext {}
