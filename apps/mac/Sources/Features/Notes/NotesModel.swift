import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class NotesModel {
    // MARK: Lifecycle

    init(store: any LibraryNoteStoring) {
        self.store = store
    }

    // MARK: Internal

    var draft: String = ""
    var selectedItemNotes: [LibraryNote] = []

    let store: any LibraryNoteStoring

    func bind(context: any LibraryContext) {
        self.context = context
    }

    func prepareNewNote() {
        guard context?.selectedItemID != nil else {
            context?.statusMessage = "Select an item first"
            return
        }

        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = ""
        }
        context?.statusMessage = "Ready for note"
    }

    func refreshForSelection() async {
        guard let selectedItemID = context?.selectedItemID else {
            selectedItemNotes = []
            return
        }

        do {
            selectedItemNotes = try await store.listNotes(itemID: selectedItemID)
        } catch {
            selectedItemNotes = []
            context?.statusMessage = "Failed to load notes"
        }
    }

    func addToSelectedItem() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            context?.statusMessage = "Enter a note first"
            return
        }

        guard let selectedItemID = context?.selectedItemID else {
            context?.statusMessage = "Select an item first"
            return
        }

        Task {
            do {
                _ = try await store.upsert(
                    LibraryNote(itemID: selectedItemID, text: text)
                )
                draft = ""
                await refreshForSelection()
                context?.statusMessage = "Added note"
            } catch {
                context?.statusMessage = "Failed to add note"
            }
        }
    }

    func remove(_ note: LibraryNote) {
        Task {
            do {
                try await store.remove(id: note.id)
                await refreshForSelection()
                context?.statusMessage = "Removed note"
            } catch {
                context?.statusMessage = "Failed to remove note"
            }
        }
    }

    /// Cascade cleanup when items are removed from the library.
    func removeItems(ids: [UUID]) async {
        try? await store.removeNotes(itemIDs: ids)
    }

    // MARK: Private

    @ObservationIgnored private weak var context: (any LibraryContext)?
}
