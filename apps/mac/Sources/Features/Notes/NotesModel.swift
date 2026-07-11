import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class NotesModel {
    // MARK: Lifecycle

    init(store: any SynchronizedLibraryNoteStoring) {
        self.store = store
    }

    // MARK: Internal

    var draft: String = ""
    var selectedItemNotes: [SynchronizedLibraryNote] = []

    let store: any SynchronizedLibraryNoteStoring

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
            selectedItemNotes = try await store.listSynchronizedNotes(itemID: selectedItemID)
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
                    LibraryNote(itemID: selectedItemID, text: Self.noteHTML(for: text))
                )
                draft = ""
                await refreshForSelection()
                context?.statusMessage = "Added note"
            } catch {
                context?.statusMessage = "Failed to add note"
            }
        }
    }

    func remove(_ note: SynchronizedLibraryNote) {
        Task {
            do {
                try await store.remove(id: note.identity.appUUID)
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

    private static func noteHTML(for text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
        return "<p>\(escaped)</p>"
    }
}
