import CitrationCore
import Foundation

extension ReaderModel {
    /// Persists a Zotero-compatible EPUB FragmentSelector without rewriting the book.
    func addEPUBAnnotation(
        selection: EPUBSelectionInfo,
        color: AnnotationColor,
        kind: AnnotationKind
    ) {
        guard let activeAttachment, activeAttachment.documentFormat == .epub else {
            context?.statusMessage = "Open an EPUB to annotate"
            return
        }
        guard kind == .highlight || kind == .underline else {
            context?.statusMessage = "Select highlight or underline"
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
                        pageLabel: "",
                        sortIndex: selection.sortIndex,
                        text: selection.text,
                        comment: "",
                        positionJSON: selection.positionJSON
                    )
                )
                await refreshAnnotations()
                context?.statusMessage = kind == .underline ? "Added EPUB underline" : "Added EPUB highlight"
            } catch {
                context?.statusMessage = "Failed to add EPUB annotation"
            }
        }
    }
}
