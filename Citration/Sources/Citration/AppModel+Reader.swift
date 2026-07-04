import Foundation

extension AppModel {
    func openReader(for attachment: LocalAttachment) {
        guard attachment.documentFormat == .pdf else {
            activeReaderAttachment = attachment
            statusMessage = "\(attachment.documentFormat.displayName) reader is not implemented yet"
            return
        }

        activeReaderAttachment = attachment
        selectedItemID = attachment.itemID
        statusMessage = "Reading \(attachment.fileName)"
        Task {
            await refreshActiveReaderAnnotations()
        }
    }

    func closeReader() {
        activeReaderAttachment = nil
        activeReaderAnnotations = []
        readerNoteDraft = ""
        statusMessage = "Ready"
    }
}
