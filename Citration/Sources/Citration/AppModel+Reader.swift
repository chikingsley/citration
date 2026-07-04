import Foundation
import CitrationCore

extension AppModel {
    func openReader(for attachment: LocalAttachment) {
        if activeReaderAttachment?.objectKey != attachment.objectKey {
            activeReaderProgress = nil
        }

        guard attachment.documentFormat == .pdf || attachment.documentFormat == .epub else {
            activeReaderAttachment = attachment
            selectedItemID = attachment.itemID
            statusMessage = "\(attachment.documentFormat.displayName) reader is not implemented yet"
            Task {
                await refreshActiveReaderProgress()
            }
            return
        }

        activeReaderAttachment = attachment
        selectedItemID = attachment.itemID
        statusMessage = "Reading \(attachment.fileName)"
        Task {
            await refreshActiveReaderProgress()
            await refreshActiveReaderAnnotations()
        }
    }

    func closeReader() {
        activeReaderAttachment = nil
        activeReaderProgress = nil
        activeReaderAnnotations = []
        readerNoteDraft = ""
        statusMessage = "Ready"
    }

    func refreshActiveReaderProgress() async {
        guard let activeReaderAttachment else {
            activeReaderProgress = nil
            return
        }

        do {
            activeReaderProgress = try await readerProgressStore.progress(
                for: activeReaderAttachment.objectKey
            )
        }
        catch {
            activeReaderProgress = nil
            statusMessage = "Failed to load reader position"
        }
    }

    func updateReaderProgress(_ progress: ReaderProgress) {
        guard activeReaderAttachment?.objectKey == progress.attachmentKey else {
            return
        }

        Task {
            do {
                activeReaderProgress = try await readerProgressStore.upsert(progress)
            }
            catch {
                statusMessage = "Failed to save reader position"
            }
        }
    }
}
