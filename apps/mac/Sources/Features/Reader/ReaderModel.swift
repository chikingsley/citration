import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class ReaderModel {
    // MARK: Lifecycle

    init(progressStore: any LibraryReaderProgressStoring, annotationStore: any SynchronizedLibraryAnnotationStoring) {
        self.progressStore = progressStore
        self.annotationStore = annotationStore
    }

    // MARK: Internal

    var activeAttachment: LocalAttachment?
    var progress: ReaderProgress?
    var annotations: [SynchronizedLibraryAnnotation] = []
    var noteDraft: String = ""
    var isInkMode = false
    var inkColor: AnnotationColor = .yellow

    let progressStore: any LibraryReaderProgressStoring
    let annotationStore: any SynchronizedLibraryAnnotationStoring

    func bind(context: any LibraryContext) {
        self.context = context
    }

    func open(_ attachment: LocalAttachment) {
        if activeAttachment?.objectKey != attachment.objectKey {
            progress = nil
        }

        guard attachment.documentFormat.isSupportedInApp else {
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
        isInkMode = false
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
            annotations = try await annotationStore.listSynchronizedAnnotations(
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
        guard activeAttachment.documentFormat == .pdf else {
            context?.statusMessage = "Creating annotations is currently available for PDFs"
            return
        }
        let pageNumber: Int = if case let .page(number) = progress?.location {
            number
        } else {
            1
        }
        guard let anchor = PDFAnnotationAnchor.note(for: activeAttachment, pageNumber: pageNumber) else {
            context?.statusMessage = "Failed to locate the current PDF page"
            return
        }

        Task {
            do {
                let annotationContext = try await annotationStore.annotationContext(
                    itemID: activeAttachment.itemID,
                    attachmentKey: activeAttachment.objectKey
                )
                _ = try await annotationStore.createSynchronizedAnnotation(
                    SynchronizedLibraryAnnotationDraft(
                        parentAttachmentIdentity: annotationContext.parentAttachmentIdentity,
                        bibliographicItemIdentity: annotationContext.bibliographicItemIdentity,
                        kind: .note,
                        color: .yellow,
                        pageLabel: anchor.pageLabel,
                        sortIndex: anchor.sortIndex,
                        text: "",
                        comment: note,
                        positionJSON: anchor.positionJSON
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

    /// Persists a highlight or underline over the given selection.
    func addHighlight(
        selection: PDFSelectionInfo,
        color: AnnotationColor,
        kind: AnnotationKind = .highlight
    ) {
        guard let activeAttachment else {
            context?.statusMessage = "Open a document first"
            return
        }

        Task {
            do {
                let annotationContext = try await annotationStore.annotationContext(
                    itemID: activeAttachment.itemID,
                    attachmentKey: activeAttachment.objectKey
                )
                _ = try await annotationStore.createSynchronizedAnnotation(
                    SynchronizedLibraryAnnotationDraft(
                        parentAttachmentIdentity: annotationContext.parentAttachmentIdentity,
                        bibliographicItemIdentity: annotationContext.bibliographicItemIdentity,
                        kind: kind,
                        color: color,
                        pageLabel: selection.anchor.pageLabel,
                        sortIndex: selection.anchor.sortIndex,
                        text: selection.text,
                        comment: "",
                        positionJSON: selection.anchor.positionJSON
                    )
                )
                await refreshAnnotations()
                context?.statusMessage = kind == .underline ? "Added underline" : "Added highlight"
            } catch {
                context?.statusMessage = "Failed to add highlight"
            }
        }
    }

    func reportMissingSelection() {
        context?.statusMessage = "Select text to highlight"
    }

    func beginInk(color: AnnotationColor) {
        guard activeAttachment?.documentFormat == .pdf else {
            context?.statusMessage = "Open a PDF to draw"
            return
        }
        inkColor = color
        isInkMode = true
        context?.statusMessage = "Drawing with \(color.rawValue) ink"
    }

    func endInk() {
        isInkMode = false
        context?.statusMessage = "Stopped drawing"
    }

    func addInk(_ stroke: PDFInkStrokeInfo) {
        guard let activeAttachment, activeAttachment.documentFormat == .pdf else {
            context?.statusMessage = "Open a PDF to draw"
            return
        }
        let color = inkColor
        Task {
            do {
                let annotationContext = try await annotationStore.annotationContext(
                    itemID: activeAttachment.itemID,
                    attachmentKey: activeAttachment.objectKey
                )
                _ = try await annotationStore.createSynchronizedAnnotation(
                    SynchronizedLibraryAnnotationDraft(
                        parentAttachmentIdentity: annotationContext.parentAttachmentIdentity,
                        bibliographicItemIdentity: annotationContext.bibliographicItemIdentity,
                        kind: .ink,
                        color: color,
                        pageLabel: stroke.anchor.pageLabel,
                        sortIndex: stroke.anchor.sortIndex,
                        text: "",
                        comment: "",
                        positionJSON: stroke.anchor.positionJSON
                    )
                )
                await refreshAnnotations()
                context?.statusMessage = "Added ink stroke"
            } catch {
                context?.statusMessage = "Failed to add ink stroke"
            }
        }
    }

    func updateAnnotation(
        _ annotation: SynchronizedLibraryAnnotation,
        kind: AnnotationKind,
        color: AnnotationColor,
        comment: String,
        tags: [ZoteroProjectedTag]
    ) {
        Task {
            do {
                _ = try await annotationStore.updateSynchronizedAnnotation(
                    SynchronizedLibraryAnnotationUpdate(
                        identity: annotation.identity,
                        kind: kind,
                        color: color,
                        comment: comment,
                        tags: tags
                    )
                )
                await refreshAnnotations()
                context?.statusMessage = "Updated annotation"
            } catch {
                context?.statusMessage = "Failed to update annotation"
            }
        }
    }

    func removeAnnotation(_ annotation: SynchronizedLibraryAnnotation) {
        Task {
            do {
                try await annotationStore.remove(id: annotation.identity.appUUID)
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
