import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class ReaderModel {
    // MARK: Lifecycle

    init(progressStore: LocalReaderProgressStore, annotationStore: LocalAnnotationStore) {
        self.progressStore = progressStore
        self.annotationStore = annotationStore
    }

    // MARK: Internal

    var activeAttachment: LocalAttachment?
    var progress: ReaderProgress?
    var annotations: [LibraryAnnotation] = []
    var noteDraft: String = ""

    let progressStore: LocalReaderProgressStore
    let annotationStore: LocalAnnotationStore

    func bind(context: any LibraryContext) {
        self.context = context
    }

    func open(_ attachment: LocalAttachment) {
        if activeAttachment?.objectKey != attachment.objectKey {
            progress = nil
        }

        guard attachment.documentFormat == .pdf || attachment.documentFormat == .epub else {
            activeAttachment = attachment
            context?.selectedItemID = attachment.itemID
            context?.statusMessage = "\(attachment.documentFormat.displayName) reader is not implemented yet"
            Task {
                await refreshProgress()
            }
            return
        }

        activeAttachment = attachment
        context?.selectedItemID = attachment.itemID
        context?.statusMessage = "Reading \(attachment.fileName)"
        Task {
            await refreshProgress()
            await refreshAnnotations()
        }
    }

    func close() {
        clear()
        context?.statusMessage = "Ready"
    }

    /// Resets reader state without touching the status message.
    func clear() {
        activeAttachment = nil
        progress = nil
        annotations = []
        noteDraft = ""
    }

    /// Clears reader state when the library selection moves to another item.
    func clearIfSelectionChanged(to itemID: UUID?) {
        if activeAttachment?.itemID != itemID {
            clear()
        }
    }

    /// Clears reader state when the active attachment disappears.
    func clearIfActiveMissing(from attachments: [LocalAttachment]) {
        guard
            let activeAttachment,
            !attachments.contains(where: { $0.id == activeAttachment.id })
        else {
            return
        }
        clear()
    }

    /// Removes persisted progress for a deleted attachment and closes it if open.
    func handleAttachmentRemoved(_ attachment: LocalAttachment) async {
        try? await progressStore.remove(attachmentKey: attachment.objectKey)
        if activeAttachment?.id == attachment.id {
            clear()
        }
    }

    /// Cascade cleanup when items are removed from the library.
    func removeItems(ids: [UUID]) async {
        try? await progressStore.removeProgress(itemIDs: ids)
    }

    func refreshProgress() async {
        guard let activeAttachment else {
            progress = nil
            return
        }

        do {
            progress = try await progressStore.progress(for: activeAttachment.objectKey)
        } catch {
            progress = nil
            context?.statusMessage = "Failed to load reader position"
        }
    }

    func updateProgress(_ newProgress: ReaderProgress) {
        guard activeAttachment?.objectKey == newProgress.attachmentKey else {
            return
        }

        Task {
            do {
                progress = try await progressStore.upsert(newProgress)
            } catch {
                context?.statusMessage = "Failed to save reader position"
            }
        }
    }

    func refreshAnnotations() async {
        guard let activeAttachment else {
            annotations = []
            return
        }

        do {
            annotations = try await annotationStore.listAnnotations(
                itemID: activeAttachment.itemID,
                attachmentKey: activeAttachment.objectKey
            )
        } catch {
            annotations = []
            context?.statusMessage = "Failed to load notes"
        }
    }

    func addNote() {
        let note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else {
            context?.statusMessage = "Enter a note first"
            return
        }

        guard let activeAttachment else {
            context?.statusMessage = "Open a document first"
            return
        }

        Task {
            do {
                _ = try await annotationStore.upsert(
                    LibraryAnnotation(
                        itemID: activeAttachment.itemID,
                        attachmentKey: activeAttachment.objectKey,
                        note: note
                    )
                )
                noteDraft = ""
                await refreshAnnotations()
                context?.statusMessage = "Added note"
            } catch {
                context?.statusMessage = "Failed to add note"
            }
        }
    }

    func removeAnnotation(_ annotation: LibraryAnnotation) {
        Task {
            do {
                try await annotationStore.remove(id: annotation.id)
                await refreshAnnotations()
                context?.statusMessage = "Removed note"
            } catch {
                context?.statusMessage = "Failed to remove note"
            }
        }
    }

    // MARK: Private

    @ObservationIgnored private weak var context: (any LibraryContext)?
}
