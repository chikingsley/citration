import CitrationCore
import PDFKit

extension ReaderModel {
    func navigate(to annotation: SynchronizedLibraryAnnotation) {
        guard
            let activeAttachment,
            annotation.parentAttachmentIdentity.objectKey == activeAttachment.objectKey,
            let location = annotation.location
        else {
            context?.statusMessage = "Annotation location is unavailable"
            return
        }

        switch location {
        case let .page(pageNumber):
            navigateToPDFPage(pageNumber, location: location, attachment: activeAttachment)

        case let .epubCFI(cfi):
            guard epubState.navigate(toCFI: cfi) else {
                context?.statusMessage = "EPUB annotation location is unavailable"
                return
            }

        case .textOffset,
             .time:
            context?.statusMessage = "Annotation navigation is unavailable for this document"
            return
        }
        context?.statusMessage = "Opened annotation"
    }

    private func navigateToPDFPage(
        _ pageNumber: Int,
        location: ReaderLocation,
        attachment: LocalAttachment
    ) {
        let pageCount = PDFDocument(url: attachment.localURL)?.pageCount ?? 0
        updateProgress(
            ReaderProgress(
                itemID: attachment.itemID,
                attachmentKey: attachment.objectKey,
                location: location,
                fractionComplete: pageCount > 0 ? Double(pageNumber) / Double(pageCount) : nil
            )
        )
    }
}
