import CitrationCore

extension IPadLibraryModel {
    func openReader(item: SynchronizedLibraryItem, record: ZoteroAttachmentCacheRecord) async {
        do {
            async let annotations = store.listSynchronizedAnnotations(
                itemID: item.identity.appUUID,
                attachmentKey: record.itemKey
            )
            async let progress = store.progress(for: record.itemKey)
            readerAnnotations = try await annotations
            readerProgress = try await progress
            statusMessage = "Reading \(record.filename)"
        } catch {
            readerAnnotations = []
            readerProgress = nil
            statusMessage = error.localizedDescription
        }
    }

    func updateReaderProgress(
        item: SynchronizedLibraryItem,
        record: ZoteroAttachmentCacheRecord,
        pageNumber: Int,
        pageCount: Int
    ) {
        let progress = ReaderProgress(
            itemID: item.identity.appUUID,
            attachmentKey: record.itemKey,
            location: .page(pageNumber),
            fractionComplete: pageCount > 0 ? Double(pageNumber) / Double(pageCount) : nil
        )
        readerProgress = progress
        Task {
            do {
                readerProgress = try await store.upsert(progress)
            } catch {
                statusMessage = "Failed to save reading position"
            }
        }
    }

    func updateEPUBProgress(
        item: SynchronizedLibraryItem,
        record: ZoteroAttachmentCacheRecord,
        cfi: String,
        fractionComplete: Double
    ) {
        let progress = ReaderProgress(
            itemID: item.identity.appUUID,
            attachmentKey: record.itemKey,
            location: .epubCFI(cfi),
            fractionComplete: fractionComplete
        )
        readerProgress = progress
        Task {
            do {
                readerProgress = try await store.upsert(progress)
            } catch {
                statusMessage = "Failed to save reading position"
            }
        }
    }

    func updateTextProgress(
        item: SynchronizedLibraryItem,
        record: ZoteroAttachmentCacheRecord,
        textOffset: Int,
        fractionComplete: Double
    ) {
        let progress = ReaderProgress(
            itemID: item.identity.appUUID,
            attachmentKey: record.itemKey,
            location: .textOffset(textOffset),
            fractionComplete: fractionComplete
        )
        readerProgress = progress
        Task {
            do {
                readerProgress = try await store.upsert(progress)
            } catch {
                statusMessage = "Failed to save reading position"
            }
        }
    }

    func createPDFAnnotation(
        item: SynchronizedLibraryItem,
        record: ZoteroAttachmentCacheRecord,
        anchor: IPadPDFAnnotationAnchor,
        kind: AnnotationKind,
        color: AnnotationColor,
        text: String = "",
        comment: String = ""
    ) async {
        do {
            let context = try await store.annotationContext(
                itemID: item.identity.appUUID,
                attachmentKey: record.itemKey
            )
            _ = try await store.createSynchronizedAnnotation(
                SynchronizedLibraryAnnotationDraft(
                    parentAttachmentIdentity: context.parentAttachmentIdentity,
                    bibliographicItemIdentity: context.bibliographicItemIdentity,
                    kind: kind,
                    color: color,
                    pageLabel: anchor.pageLabel,
                    sortIndex: anchor.sortIndex,
                    text: text,
                    comment: comment,
                    positionJSON: anchor.positionJSON
                )
            )
            readerAnnotations = try await store.listSynchronizedAnnotations(
                itemID: item.identity.appUUID,
                attachmentKey: record.itemKey
            )
            statusMessage = kind == .ink ? "Added Pencil annotation" : "Added \(kind.rawValue)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createEPUBAnnotation(
        item: SynchronizedLibraryItem,
        record: ZoteroAttachmentCacheRecord,
        selection: EPUBSelectionInfo,
        kind: AnnotationKind,
        color: AnnotationColor
    ) async {
        do {
            let context = try await store.annotationContext(
                itemID: item.identity.appUUID,
                attachmentKey: record.itemKey
            )
            _ = try await store.createSynchronizedAnnotation(
                SynchronizedLibraryAnnotationDraft(
                    parentAttachmentIdentity: context.parentAttachmentIdentity,
                    bibliographicItemIdentity: context.bibliographicItemIdentity,
                    kind: kind,
                    color: color,
                    pageLabel: "",
                    sortIndex: selection.sortIndex,
                    text: selection.text,
                    comment: "",
                    positionJSON: selection.positionJSON
                )
            )
            readerAnnotations = try await store.listSynchronizedAnnotations(
                itemID: item.identity.appUUID,
                attachmentKey: record.itemKey
            )
            statusMessage = "Added EPUB \(kind.rawValue)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
