import CitrationCore
import Foundation

extension AppModel {
    func prepareNewItemNote() {
        guard selectedItemID != nil else {
            statusMessage = "Select an item first"
            return
        }

        if itemNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            itemNoteDraft = ""
        }
        statusMessage = "Ready for note"
    }

    func refreshSelectedItemNotes() async {
        guard let selectedItemID else {
            selectedItemNotes = []
            return
        }

        do {
            selectedItemNotes = try await noteStore.listNotes(itemID: selectedItemID)
        } catch {
            selectedItemNotes = []
            statusMessage = "Failed to load notes"
        }
    }

    func addNoteToSelectedItem() {
        let text = itemNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = "Enter a note first"
            return
        }

        guard let selectedItemID else {
            statusMessage = "Select an item first"
            return
        }

        Task {
            do {
                _ = try await noteStore.upsert(
                    LibraryNote(itemID: selectedItemID, text: text)
                )
                itemNoteDraft = ""
                await refreshSelectedItemNotes()
                statusMessage = "Added note"
            } catch {
                statusMessage = "Failed to add note"
            }
        }
    }

    func removeItemNote(_ note: LibraryNote) {
        Task {
            do {
                try await noteStore.remove(id: note.id)
                await refreshSelectedItemNotes()
                statusMessage = "Removed note"
            } catch {
                statusMessage = "Failed to remove note"
            }
        }
    }
}
