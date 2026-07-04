import Foundation
import CitrationCore

extension AppModel {
    func importAttachments(urls: [URL], mode: AttachmentImportMode = .auto) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            statusMessage = "No valid files to import"
            return
        }

        guard let plan = attachmentImportPlan(mode: mode) else {
            statusMessage = "Select an item to attach files"
            return
        }

        let noun = fileURLs.count == 1 ? "file" : "files"
        statusMessage = "Importing \(fileURLs.count) \(noun)..."
        isImportingAttachments = true

        Task { @MainActor in
            defer {
                isImportingAttachments = false
            }

            let summary: AttachmentImportSummary
            if let targetItem = plan.targetItem {
                summary = await importFiles(fileURLs, attachingTo: targetItem)
            }
            else {
                summary = await importFilesAsNewItems(fileURLs)
            }

            await refreshItems()
            updateImportStatus(summary)
        }
    }

    func reprocessSelectedItemAttachments() {
        guard let selectedItem else {
            statusMessage = "Select an item first"
            return
        }

        let targetItemID = selectedItem.id
        reprocessingItemID = targetItemID
        statusMessage = "Processing attachments..."

        Task { @MainActor in
            let summary = await reprocessAttachments(for: selectedItem, targetItemID: targetItemID)
            updateReprocessStatus(summary)
        }
    }

    func removeAttachment(_ attachment: LocalAttachment) {
        Task {
            do {
                try await attachmentStore.removeAttachment(attachment)
                try? await readerProgressStore.remove(attachmentKey: attachment.objectKey)
                if activeReaderAttachment?.id == attachment.id {
                    activeReaderAttachment = nil
                    activeReaderProgress = nil
                }
                await refreshSelectedItemAttachments()
                statusMessage = "Removed attachment"
            }
            catch {
                statusMessage = "Failed to remove attachment"
            }
        }
    }

    func refreshSelectedItemAttachments() async {
        guard let selectedItemID else {
            selectedItemAttachments = []
            return
        }

        do {
            selectedItemAttachments = try await attachmentStore.listAttachments(for: selectedItemID)
            if let activeReaderAttachment,
               !selectedItemAttachments.contains(where: { $0.id == activeReaderAttachment.id }) {
                self.activeReaderAttachment = nil
                activeReaderProgress = nil
            }
        }
        catch {
            selectedItemAttachments = []
            activeReaderAttachment = nil
            activeReaderProgress = nil
            statusMessage = "Failed to load attachments"
        }
    }
}

private extension AppModel {
    func attachmentImportPlan(mode: AttachmentImportMode) -> AttachmentImportPlan? {
        switch mode {
        case .attachToSelectedItem:
            return selectedItem.map { AttachmentImportPlan(targetItem: $0) }
        case .auto:
            return AttachmentImportPlan(targetItem: selectedItem)
        case .createNewItemPerFile:
            return AttachmentImportPlan(targetItem: nil)
        }
    }

    func importFiles(
        _ urls: [URL],
        attachingTo targetItem: BCItem
    ) async -> AttachmentImportSummary {
        var currentItem = targetItem
        var summary = AttachmentImportSummary()

        for url in urls {
            do {
                let attachment = try await attachmentStore.importFile(from: url, for: currentItem)
                if currentItem.id == selectedItemID {
                    await refreshSelectedItemAttachments()
                }
                let enrichment = await enrichImportedAttachment(item: currentItem, attachment: attachment)
                currentItem = enrichment.item
                summary.recordSuccessfulImport(enrichment)
            }
            catch {
                summary.failedFiles.append(url.lastPathComponent)
            }
        }

        return summary
    }

    func importFilesAsNewItems(_ urls: [URL]) async -> AttachmentImportSummary {
        var summary = AttachmentImportSummary()

        for url in urls {
            var item = BCItem(title: inferredTitle(from: url))
            await store.upsert(item)
            selectedItemID = item.id
            await refreshItems()

            do {
                let attachment = try await attachmentStore.importFile(from: url, for: item)
                if item.id == selectedItemID {
                    await refreshSelectedItemAttachments()
                }
                await refreshItems()
                let enrichment = await enrichImportedAttachment(item: item, attachment: attachment)
                item = enrichment.item
                await addItemToSelectedCollectionIfNeeded(item.id)
                selectedItemID = item.id
                summary.recordSuccessfulImport(enrichment)
            }
            catch {
                await store.removeItem(id: item.id)
                await refreshItems()
                summary.failedFiles.append(url.lastPathComponent)
            }
        }

        return summary
    }

    func reprocessAttachments(
        for selectedItem: BCItem,
        targetItemID: UUID
    ) async -> AttachmentReprocessSummary {
        defer {
            if reprocessingItemID == targetItemID {
                reprocessingItemID = nil
            }
        }

        await refreshSelectedItemAttachments()

        var currentItem = selectedItem
        var summary = AttachmentReprocessSummary()

        for attachment in selectedItemAttachments where shouldAttemptDOIExtraction(for: attachment) {
            let enrichment = await enrichImportedAttachment(item: currentItem, attachment: attachment)
            currentItem = enrichment.item
            summary.recordProcessedAttachment(enrichment)
        }

        await refreshItems()
        selectedItemID = currentItem.id
        return summary
    }

    func updateImportStatus(_ summary: AttachmentImportSummary) {
        if summary.importedCount > 0, summary.failedFiles.isEmpty {
            let importedNoun = summary.importedCount == 1 ? "file" : "files"
            statusMessage = "Imported \(summary.importedCount) \(importedNoun)"
        }
        else if summary.importedCount > 0 {
            statusMessage = "Imported \(summary.importedCount), failed \(summary.failedFiles.count)"
        }
        else {
            statusMessage = "Import failed"
        }

        appendDetectedDOIStatus(summary.detectedDOIs)
    }

    func updateReprocessStatus(_ summary: AttachmentReprocessSummary) {
        guard summary.processedCount > 0 else {
            statusMessage = "No PDF attachments to process"
            return
        }

        let noun = summary.processedCount == 1 ? "attachment" : "attachments"
        statusMessage = "Processed \(summary.processedCount) \(noun)"
        appendDetectedDOIStatus(summary.detectedDOIs)
    }

    func appendDetectedDOIStatus(_ detectedDOIs: Set<String>) {
        guard !detectedDOIs.isEmpty else {
            return
        }

        let noun = detectedDOIs.count == 1 ? "DOI" : "DOIs"
        statusMessage += " · detected \(detectedDOIs.count) \(noun)"
    }
}

private struct AttachmentImportPlan {
    var targetItem: BCItem?
}

private struct AttachmentImportSummary {
    var importedCount = 0
    var failedFiles = [String]()
    var detectedDOIs = Set<String>()

    mutating func recordSuccessfulImport(_ enrichment: AttachmentEnrichment) {
        importedCount += 1
        if let doi = enrichment.detectedDOI {
            detectedDOIs.insert(doi)
        }
    }
}

private struct AttachmentReprocessSummary {
    var processedCount = 0
    var detectedDOIs = Set<String>()

    mutating func recordProcessedAttachment(_ enrichment: AttachmentEnrichment) {
        processedCount += 1
        if let doi = enrichment.detectedDOI {
            detectedDOIs.insert(doi)
        }
    }
}
