import CitrationCore
import Foundation

extension AppModel {
    func refreshActiveReaderAnnotations() async {
        guard let activeReaderAttachment else {
            activeReaderAnnotations = []
            return
        }

        do {
            activeReaderAnnotations = try await annotationStore.listAnnotations(
                itemID: activeReaderAttachment.itemID,
                attachmentKey: activeReaderAttachment.objectKey
            )
        } catch {
            activeReaderAnnotations = []
            statusMessage = "Failed to load notes"
        }
    }

    func addReaderNote() {
        let note = readerNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else {
            statusMessage = "Enter a note first"
            return
        }

        guard let activeReaderAttachment else {
            statusMessage = "Open a document first"
            return
        }

        Task {
            do {
                _ = try await annotationStore.upsert(
                    LibraryAnnotation(
                        itemID: activeReaderAttachment.itemID,
                        attachmentKey: activeReaderAttachment.objectKey,
                        note: note
                    )
                )
                readerNoteDraft = ""
                await refreshActiveReaderAnnotations()
                statusMessage = "Added note"
            } catch {
                statusMessage = "Failed to add note"
            }
        }
    }

    func removeReaderAnnotation(_ annotation: LibraryAnnotation) {
        Task {
            do {
                try await annotationStore.remove(id: annotation.id)
                await refreshActiveReaderAnnotations()
                statusMessage = "Removed note"
            } catch {
                statusMessage = "Failed to remove note"
            }
        }
    }
}
