import CitrationCore
import Foundation
import Observation

// MARK: - AttachmentImportMode

enum AttachmentImportMode {
    case auto
    case attachToSelectedItem
    case createNewItemPerFile
}

// MARK: - ImportModel

@MainActor
@Observable
final class ImportModel {
    // MARK: Lifecycle

    init(
        store: any BCItemStore,
        attachmentStore: any LibraryAttachmentStoring,
        metadataRegistry: MetadataProviderRegistry,
        pdfDOIExtractor: any PDFDOIExtracting,
        ocrService: any OCRServicing = MistralOCRService()
    ) {
        self.store = store
        self.attachmentStore = attachmentStore
        self.metadataRegistry = metadataRegistry
        self.pdfDOIExtractor = pdfDOIExtractor
        self.ocrService = ocrService
    }

    // MARK: Internal

    var doiInput: String = ""
    var isResolvingDOI: Bool = false
    var isImporting: Bool = false
    var reprocessingItemID: UUID?
    var metadataWarnings: [String] = []
    var metadataConflicts: [MetadataResolutionConflict] = []
    var selectedItemAttachments: [LocalAttachment] = []

    let attachmentStore: any LibraryAttachmentStoring

    var isReprocessing: Bool {
        reprocessingItemID != nil
    }

    var hasMetadataDiagnostics: Bool {
        !metadataWarnings.isEmpty || !metadataConflicts.isEmpty
    }

    func bind(context: any LibraryContext, collections: CollectionsModel, reader: ReaderModel) {
        self.context = context
        self.collections = collections
        self.reader = reader
    }

    // MARK: - DOI entry

    func addByDOI() {
        guard let doi = normalizedDOIInput() else {
            return
        }

        clearMetadataDiagnostics()
        isResolvingDOI = true
        context?.statusMessage = "Resolving DOI \(doi)..."

        Task {
            let request = MetadataResolutionRequest(
                identifiers: [Identifier(type: .doi, value: doi)]
            )
            let result = await metadataRegistry.resolveAll(request)
            recordMetadataDiagnostics(result)

            guard let best = result.bestMatch else {
                isResolvingDOI = false
                context?.statusMessage = "No metadata found for \(doi)"
                return
            }

            let fallbackItem = BCItem(title: "Untitled Item")
            let item = BCItem(
                title: MetadataMerging.normalizedTitle(best.title) ?? "Untitled Item",
                identifiers: MetadataMerging.mergeIdentifiers(
                    best.identifiers + [Identifier(type: .doi, value: doi)],
                    into: fallbackItem
                ).identifiers,
                itemType: best.itemType,
                creators: MetadataMerging.normalizedCreators(best.creators),
                publicationYear: best.publicationYear
            )

            await store.upsert(item)
            context?.selectedItemID = item.id
            await context?.refreshLibrary()
            doiInput = ""
            isResolvingDOI = false
            context?.statusMessage = "Added: \(item.title)"
            appendMetadataDiagnosticsStatus()
        }
    }

    // MARK: - Attachment import

    func importAttachments(urls: [URL], mode: AttachmentImportMode = .auto) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            context?.statusMessage = "No valid files to import"
            return
        }

        guard let plan = attachmentImportPlan(mode: mode) else {
            context?.statusMessage = "Select an item to attach files"
            return
        }

        clearMetadataDiagnostics()
        let noun = fileURLs.count == 1 ? "file" : "files"
        context?.statusMessage = "Importing \(fileURLs.count) \(noun)..."
        isImporting = true

        Task { @MainActor in
            defer {
                isImporting = false
            }

            let summary: AttachmentImportSummary = if let targetItem = plan.targetItem {
                await importFiles(fileURLs, attachingTo: targetItem)
            } else {
                await importFilesAsNewItems(fileURLs)
            }

            await context?.refreshLibrary()
            updateImportStatus(summary)
        }
    }

    func reprocessSelectedItemAttachments() {
        guard let selectedItem = context?.selectedItem else {
            context?.statusMessage = "Select an item first"
            return
        }

        let targetItemID = selectedItem.id
        clearMetadataDiagnostics()
        reprocessingItemID = targetItemID
        context?.statusMessage = "Processing attachments..."

        Task { @MainActor in
            let summary = await reprocessAttachments(for: selectedItem, targetItemID: targetItemID)
            updateReprocessStatus(summary)
        }
    }

    func removeAttachment(_ attachment: LocalAttachment) {
        Task {
            do {
                try await attachmentStore.removeAttachment(attachment)
                await reader?.handleAttachmentRemoved(attachment)
                await refreshSelectedItemAttachments()
                context?.statusMessage = "Removed attachment"
            } catch {
                context?.statusMessage = "Failed to remove attachment"
            }
        }
    }

    func refreshSelectedItemAttachments() async {
        guard let selectedItemID = context?.selectedItemID else {
            selectedItemAttachments = []
            return
        }

        do {
            selectedItemAttachments = try await attachmentStore.listAttachments(for: selectedItemID)
            reader?.clearIfActiveMissing(from: selectedItemAttachments)
        } catch {
            selectedItemAttachments = []
            reader?.clear()
            context?.statusMessage = "Failed to load attachments"
        }
    }

    // MARK: - Metadata enrichment

    // MARK: - Diagnostics

    func clearMetadataDiagnostics() {
        metadataWarnings = []
        metadataConflicts = []
    }

    func recordMetadataDiagnostics(_ result: MetadataResolutionResult) {
        metadataWarnings = result.warnings
        metadataConflicts = result.conflicts
    }

    func appendMetadataDiagnosticsStatus() {
        guard !metadataConflicts.isEmpty else {
            return
        }

        context?.statusMessage += " · check metadata"
    }

    // MARK: Private

    @ObservationIgnored private weak var context: (any LibraryContext)?

    @ObservationIgnored private weak var collections: CollectionsModel?

    @ObservationIgnored private weak var reader: ReaderModel?

    private let store: any BCItemStore
    private let metadataRegistry: MetadataProviderRegistry
    private let pdfDOIExtractor: any PDFDOIExtracting
    private let ocrService: any OCRServicing

    private func attachmentImportPlan(mode: AttachmentImportMode) -> AttachmentImportPlan? {
        switch mode {
        case .attachToSelectedItem:
            context?.selectedItem.map { AttachmentImportPlan(targetItem: $0) }
        case .auto:
            AttachmentImportPlan(targetItem: context?.selectedItem)
        case .createNewItemPerFile:
            AttachmentImportPlan(targetItem: nil)
        }
    }

    private func importFiles(
        _ urls: [URL],
        attachingTo targetItem: BCItem
    ) async -> AttachmentImportSummary {
        var currentItem = targetItem
        var summary = AttachmentImportSummary()

        for url in urls {
            do {
                let attachment = try await attachmentStore.importFile(from: url, for: currentItem)
                if currentItem.id == context?.selectedItemID {
                    await refreshSelectedItemAttachments()
                }
                let enrichment = await enrichImportedAttachment(item: currentItem, attachment: attachment)
                currentItem = enrichment.item
                summary.recordSuccessfulImport(enrichment)
            } catch {
                summary.failedFiles.append(url.lastPathComponent)
            }
        }

        return summary
    }

    private func importFilesAsNewItems(_ urls: [URL]) async -> AttachmentImportSummary {
        var summary = AttachmentImportSummary()

        for url in urls {
            var item = BCItem(title: MetadataMerging.inferredTitle(from: url))
            await store.upsert(item)
            context?.selectedItemID = item.id
            await context?.refreshLibrary()

            do {
                let attachment = try await attachmentStore.importFile(from: url, for: item)
                if item.id == context?.selectedItemID {
                    await refreshSelectedItemAttachments()
                }
                await context?.refreshLibrary()
                let enrichment = await enrichImportedAttachment(item: item, attachment: attachment)
                item = enrichment.item
                await collections?.fileInSelectedCollection(item.id)
                context?.selectedItemID = item.id
                summary.recordSuccessfulImport(enrichment)
            } catch {
                await store.removeItem(id: item.id)
                await context?.refreshLibrary()
                summary.failedFiles.append(url.lastPathComponent)
            }
        }

        return summary
    }

    private func reprocessAttachments(
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

        await context?.refreshLibrary()
        context?.selectedItemID = currentItem.id
        return summary
    }

    private func updateImportStatus(_ summary: AttachmentImportSummary) {
        if summary.importedCount > 0, summary.failedFiles.isEmpty {
            let importedNoun = summary.importedCount == 1 ? "file" : "files"
            context?.statusMessage = "Imported \(summary.importedCount) \(importedNoun)"
        } else if summary.importedCount > 0 {
            context?.statusMessage = "Imported \(summary.importedCount), failed \(summary.failedFiles.count)"
        } else {
            context?.statusMessage = "Import failed"
        }

        appendDetectedDOIStatus(summary.detectedDOIs)
        appendMetadataDiagnosticsStatus()
    }

    private func updateReprocessStatus(_ summary: AttachmentReprocessSummary) {
        guard summary.processedCount > 0 else {
            context?.statusMessage = "No PDF attachments to process"
            return
        }

        let noun = summary.processedCount == 1 ? "attachment" : "attachments"
        context?.statusMessage = "Processed \(summary.processedCount) \(noun)"
        appendDetectedDOIStatus(summary.detectedDOIs)
        appendMetadataDiagnosticsStatus()
    }

    private func appendDetectedDOIStatus(_ detectedDOIs: Set<String>) {
        guard !detectedDOIs.isEmpty else {
            return
        }

        let noun = detectedDOIs.count == 1 ? "DOI" : "DOIs"
        context?.statusMessage += " · detected \(detectedDOIs.count) \(noun)"
    }

    private func normalizedDOIInput() -> String? {
        guard let trimmed = doiInput.bcTrimmedNonEmpty else {
            context?.statusMessage = "Enter a DOI first"
            return nil
        }
        guard let doi = DOIParsing.normalizeCandidate(trimmed) else {
            context?.statusMessage = "Enter a valid DOI"
            return nil
        }
        return doi
    }
}

// MARK: - AttachmentEnrichment

struct AttachmentEnrichment {
    var item: BCItem
    var detectedDOI: String?
}

// MARK: - AttachmentImportPlan

private struct AttachmentImportPlan {
    var targetItem: BCItem?
}

// MARK: - AttachmentImportSummary

private struct AttachmentImportSummary {
    var importedCount = 0
    var failedFiles: [String] = []
    var detectedDOIs: Set<String> = []

    mutating func recordSuccessfulImport(_ enrichment: AttachmentEnrichment) {
        importedCount += 1
        if let doi = enrichment.detectedDOI {
            detectedDOIs.insert(doi)
        }
    }
}

// MARK: - AttachmentReprocessSummary

private struct AttachmentReprocessSummary {
    var processedCount = 0
    var detectedDOIs: Set<String> = []

    mutating func recordProcessedAttachment(_ enrichment: AttachmentEnrichment) {
        processedCount += 1
        if let doi = enrichment.detectedDOI {
            detectedDOIs.insert(doi)
        }
    }
}

// MARK: - Metadata enrichment

extension ImportModel {
    func enrichImportedAttachment(
        item: BCItem,
        attachment: LocalAttachment
    ) async -> AttachmentEnrichment {
        guard shouldAttemptDOIExtraction(for: attachment), item.doi == nil else {
            return AttachmentEnrichment(item: item, detectedDOI: nil)
        }

        var candidates = await pdfDOIExtractor.extractCandidates(from: attachment.localURL)

        if
            candidates.isEmpty,
            !PDFKitDOIExtractor.hasTextLayer(at: attachment.localURL),
            await ocrService.isConfigured()
        {
            context?.statusMessage = "Running OCR on \(attachment.fileName)..."
            if let markdown = try? await ocrService.recognizeText(from: attachment.localURL) {
                candidates = OCRTextParsing.candidates(fromMarkdown: markdown)
            }
        }

        let fallbackTitleQuery = MetadataMerging.metadataFallbackTitle(for: item, attachment: attachment)

        let resolver = PDFMetadataResolver(registry: metadataRegistry) { [weak self] result in
            self?.recordMetadataDiagnostics(result)
        }
        if let best = await resolver.resolve(candidates: candidates, fallbackTitleQuery: fallbackTitleQuery) {
            let enriched = MetadataMerging.mergeMetadata(best, into: item, fallbackDOI: candidates.detectedDOI)
            await store.upsert(enriched)
            return AttachmentEnrichment(item: enriched, detectedDOI: candidates.detectedDOI)
        }

        guard !candidates.isEmpty else {
            return AttachmentEnrichment(item: item, detectedDOI: nil)
        }

        var withDetectedIdentifiers = MetadataMerging.mergeIdentifiers(candidates.identifiers, into: item)
        if
            let ocrTitle = candidates.titleHints.first,
            hasPlaceholderTitle(withDetectedIdentifiers, attachment: attachment)
        {
            withDetectedIdentifiers.title = ocrTitle
        }
        await store.upsert(withDetectedIdentifiers)
        return AttachmentEnrichment(item: withDetectedIdentifiers, detectedDOI: candidates.detectedDOI)
    }

    func shouldAttemptDOIExtraction(for attachment: LocalAttachment) -> Bool {
        attachment.documentFormat == .pdf
    }

    /// True while the item still carries an auto-generated title (from
    /// the filename or the "Untitled Item" default) that an OCR-derived
    /// title should replace.
    private func hasPlaceholderTitle(_ item: BCItem, attachment: LocalAttachment) -> Bool {
        item.title == "Untitled Item"
            || item.title == MetadataMerging.inferredTitle(from: attachment.localURL)
    }
}
