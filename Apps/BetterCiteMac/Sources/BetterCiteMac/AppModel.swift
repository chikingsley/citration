import Foundation
import Observation
import BCStorage
import BCMetadataProviders
import BCCitationEngine
import BCDataLocal
import BCDataRemote
import BCDomain
import BCCommon

@MainActor
@Observable
final class AppModel {
    enum Route: String, CaseIterable, Identifiable {
        case workspace
        case components

        var id: String { rawValue }

        var title: String {
            switch self {
            case .workspace:
                return "Workspace"
            case .components:
                return "Components"
            }
        }
    }

    enum AttachmentImportMode {
        case auto
        case attachToSelectedItem
        case createNewItemPerFile
    }

    var route: Route = .workspace
    var doiInput: String = ""
    var isResolvingDOI: Bool = false
    var isImportingAttachments: Bool = false
    var reprocessingItemID: UUID?
    var isReprocessingAttachments: Bool { reprocessingItemID != nil }
    var statusMessage: String = "Ready"

    var items: [BCItem] = []
    var selectedItemID: UUID?
    var citationPreview: String = "Select an item to preview citation output"
    var selectedItemAttachments: [LocalAttachment] = []

    var storageConnectors: [StorageConnector]

    // Auth state
    var isSignedIn: Bool = false
    var currentUser: User?
    private(set) var authService: AuthService?
    private(set) var workspaceService: WorkspaceService?
    private let sessionStore: AuthSessionStore

    private let store: any BCItemStore
    private let metadataRegistry: MetadataProviderRegistry
    private let citationFormatter: any CitationFormattingEngine
    private let attachmentStore: LocalAttachmentStore
    private let pdfDOIExtractor: any PDFDOIExtracting

    init(
        store: any BCItemStore,
        metadataRegistry: MetadataProviderRegistry,
        citationFormatter: any CitationFormattingEngine,
        storageConnectors: [StorageConnector],
        sessionStore: AuthSessionStore = InMemoryAuthSessionStore(),
        pdfDOIExtractor: any PDFDOIExtracting = NullPDFDOIExtractor(),
        attachmentStore: LocalAttachmentStore? = nil
    ) {
        self.store = store
        self.metadataRegistry = metadataRegistry
        self.citationFormatter = citationFormatter
        self.storageConnectors = storageConnectors
        self.sessionStore = sessionStore
        self.attachmentStore = attachmentStore ?? AppModel.makeAttachmentStore()
        self.pdfDOIExtractor = pdfDOIExtractor

        Task {
            await setupAuthServices()
            await refreshItems()
        }
    }

    static func bootstrap() -> AppModel {
        let store: any BCItemStore
        do {
            let storeURL = try BCDataLocalPaths.defaultItemStoreURL()
            store = try SwiftDataItemStore(storeURL: storeURL)
        }
        catch {
            assertionFailure("Failed to initialize SwiftData item store: \(error)")
            store = InMemoryItemStore()
        }

        let providers: [any MetadataProvider] = [
            ArXivMetadataProvider(),
            CrossrefDOIMetadataProvider(),
            OpenLibraryISBNMetadataProvider()
        ]
        let metadataRegistry = MetadataProviderRegistry(providers: providers)
        let citationFormatter = StubCitationFormatter()
        let pdfDOIExtractor = MuPDFDOIExtractor()
        let storageConnectors = [
            StorageConnector(name: "Local Files", type: .local, bucket: "local", isDefault: true)
        ]
        let sessionStore = KeychainAuthSessionStore()

        return AppModel(
            store: store,
            metadataRegistry: metadataRegistry,
            citationFormatter: citationFormatter,
            storageConnectors: storageConnectors,
            sessionStore: sessionStore,
            pdfDOIExtractor: pdfDOIExtractor
        )
    }

    // MARK: - Auth

    private func setupAuthServices() async {
        guard let environment = try? SaaSEnvironment(rootDomain: "bettercite.app") else { return }

        let apiClient = APIClient(environment: environment, sessionStore: sessionStore)
        let authService = AuthService(apiClient: apiClient, sessionStore: sessionStore, environment: environment)
        let workspaceService = WorkspaceService(apiClient: apiClient)

        self.authService = authService
        self.workspaceService = workspaceService

        // Check for existing session
        isSignedIn = await authService.hasValidSession()
        if isSignedIn {
            currentUser = try? await authService.currentUser()
        }
    }

    func signInWithApple(identityToken: String) async throws {
        guard let authService else { return }
        _ = try await authService.signInWithApple(identityToken: identityToken)
        isSignedIn = true
        currentUser = try? await authService.currentUser()
    }

    func signOut() async {
        guard let authService else { return }
        try? await authService.signOut()
        isSignedIn = false
        currentUser = nil
    }

    var selectedItem: BCItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    func refreshItems() async {
        items = await store.listItems()
        let hasValidSelection = selectedItemID.map { selectedID in
            items.contains { $0.id == selectedID }
        } ?? false
        if !hasValidSelection {
            selectedItemID = items.first?.id
        }
        await renderCitationPreviewForSelection()
        await refreshSelectedItemAttachments()
    }

    func addEmptyItem() {
        Task {
            let item = BCItem(title: "Untitled Item")
            await store.upsert(item)
            await refreshItems()
            selectedItemID = item.id
            statusMessage = "Added: \(item.title)"
        }
    }

    func addByDOI() {
        let rawInput = doiInput
        guard let trimmed = rawInput.bcTrimmedNonEmpty else {
            statusMessage = "Enter a DOI first"
            return
        }
        guard let doi = DOIParsing.normalizeCandidate(trimmed) else {
            statusMessage = "Enter a valid DOI"
            return
        }

        isResolvingDOI = true
        statusMessage = "Resolving DOI \(doi)..."

        Task {
            let request = MetadataResolutionRequest(
                identifiers: [Identifier(type: .doi, value: doi)]
            )
            let result = await metadataRegistry.resolveAll(request)

            guard let best = result.bestMatch else {
                isResolvingDOI = false
                statusMessage = "No metadata found for \(doi)"
                return
            }

            let item = BCItem(
                title: normalizedTitle(best.title) ?? "Untitled Item",
                identifiers: mergeIdentifiers(best.identifiers + [Identifier(type: .doi, value: doi)], into: BCItem(title: "Untitled Item")).identifiers,
                itemType: best.itemType,
                creators: normalizedCreators(best.creators),
                publicationYear: best.publicationYear
            )

            await store.upsert(item)
            await refreshItems()
            selectedItemID = item.id
            doiInput = ""
            isResolvingDOI = false
            statusMessage = "Added: \(item.title)"
            await renderCitationPreviewForSelection()
        }
    }

    func removeSelectedItem() {
        guard let selectedItemID else { return }

        removeItems(ids: [selectedItemID])
    }

    func removeItems(ids: [UUID]) {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return }

        Task { @MainActor in
            for id in uniqueIDs {
                await store.removeItem(id: id)
            }
            await refreshItems()

            if uniqueIDs.count == 1 {
                statusMessage = "Removed item"
            } else {
                statusMessage = "Removed \(uniqueIDs.count) items"
            }
        }
    }

    func selectItem(id: UUID?) {
        selectedItemID = id
        Task {
            await renderCitationPreviewForSelection()
            await refreshSelectedItemAttachments()
        }
    }

    func importAttachments(urls: [URL], mode: AttachmentImportMode = .auto) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            statusMessage = "No valid files to import"
            return
        }

        let selectedItemAtDrop = selectedItem
        let targetItem: BCItem? = switch mode {
        case .attachToSelectedItem:
            selectedItemAtDrop
        case .auto:
            selectedItemAtDrop
        case .createNewItemPerFile:
            nil
        }

        if mode == .attachToSelectedItem, targetItem == nil {
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

            var importedCount = 0
            var failedFiles = [String]()
            var detectedDOIs = Set<String>()

            if let targetItem {
                var currentItem = targetItem
                for url in fileURLs {
                    do {
                        let attachment = try await attachmentStore.importFile(from: url, for: currentItem)
                        if currentItem.id == selectedItemID {
                            await refreshSelectedItemAttachments()
                        }
                        let enrichment = await enrichImportedAttachment(item: currentItem, attachment: attachment)
                        currentItem = enrichment.item
                        if let doi = enrichment.detectedDOI {
                            detectedDOIs.insert(doi)
                        }
                        importedCount += 1
                    }
                    catch {
                        failedFiles.append(url.lastPathComponent)
                    }
                }
            } else {
                for url in fileURLs {
                    let title = inferredTitle(from: url)
                    var item = BCItem(title: title)
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
                        if let doi = enrichment.detectedDOI {
                            detectedDOIs.insert(doi)
                        }
                        selectedItemID = item.id
                        importedCount += 1
                    }
                    catch {
                        // Avoid leaving behind orphan items when file copy/import fails.
                        await store.removeItem(id: item.id)
                        await refreshItems()
                        failedFiles.append(url.lastPathComponent)
                    }
                }
            }

            await refreshItems()

            if importedCount > 0, failedFiles.isEmpty {
                let importedNoun = importedCount == 1 ? "file" : "files"
                statusMessage = "Imported \(importedCount) \(importedNoun)"
            } else if importedCount > 0 {
                statusMessage = "Imported \(importedCount), failed \(failedFiles.count)"
            } else {
                statusMessage = "Import failed"
            }

            if !detectedDOIs.isEmpty {
                let noun = detectedDOIs.count == 1 ? "DOI" : "DOIs"
                statusMessage += " · detected \(detectedDOIs.count) \(noun)"
            }
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
            defer {
                if reprocessingItemID == targetItemID {
                    reprocessingItemID = nil
                }
            }

            await refreshSelectedItemAttachments()

            var currentItem = selectedItem
            var processedCount = 0
            var detectedDOIs = Set<String>()

            for attachment in selectedItemAttachments {
                guard shouldAttemptDOIExtraction(for: attachment) else {
                    continue
                }
                let enrichment = await enrichImportedAttachment(item: currentItem, attachment: attachment)
                currentItem = enrichment.item
                if let doi = enrichment.detectedDOI {
                    detectedDOIs.insert(doi)
                }
                processedCount += 1
            }

            await refreshItems()
            selectedItemID = currentItem.id

            if processedCount == 0 {
                statusMessage = "No PDF attachments to process"
                return
            }

            let noun = processedCount == 1 ? "attachment" : "attachments"
            statusMessage = "Processed \(processedCount) \(noun)"
            if !detectedDOIs.isEmpty {
                let doiNoun = detectedDOIs.count == 1 ? "DOI" : "DOIs"
                statusMessage += " · detected \(detectedDOIs.count) \(doiNoun)"
            }
        }
    }

    func removeAttachment(_ attachment: LocalAttachment) {
        Task {
            do {
                try await attachmentStore.removeAttachment(attachment)
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
        }
        catch {
            selectedItemAttachments = []
            statusMessage = "Failed to load attachments"
        }
    }

    private func inferredTitle(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let replaced = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .bcCollapsedWhitespace()
        return replaced.isEmpty ? "Untitled Item" : replaced
    }

    private static func makeAttachmentStore() -> LocalAttachmentStore {
        do {
            let baseDirectory = try LocalAttachmentStorePaths.defaultBaseDirectory()
            return try LocalAttachmentStore(baseDirectory: baseDirectory)
        }
        catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("better-cite", isDirectory: true)
                .appendingPathComponent("attachments", isDirectory: true)
            do {
                return try LocalAttachmentStore(baseDirectory: fallback)
            }
            catch {
                fatalError("Unable to initialize attachment store: \(error)")
            }
        }
    }

    private struct AttachmentEnrichment {
        var item: BCItem
        var detectedDOI: String?
    }

    private func enrichImportedAttachment(item: BCItem, attachment: LocalAttachment) async -> AttachmentEnrichment {
        guard shouldAttemptDOIExtraction(for: attachment) else {
            return AttachmentEnrichment(item: item, detectedDOI: nil)
        }

        if item.doi != nil {
            return AttachmentEnrichment(item: item, detectedDOI: nil)
        }

        let candidates = await pdfDOIExtractor.extractCandidates(from: attachment.localURL)
        guard !candidates.isEmpty else {
            return AttachmentEnrichment(item: item, detectedDOI: nil)
        }

        if let best = await resolveMetadataForPDFCandidates(candidates) {
            let enriched = mergeMetadata(best, into: item, fallbackDOI: candidates.detectedDOI)
            await store.upsert(enriched)
            return AttachmentEnrichment(item: enriched, detectedDOI: candidates.detectedDOI)
        }

        let withDetectedIdentifiers = mergeIdentifiers(candidates.identifiers, into: item)
        await store.upsert(withDetectedIdentifiers)
        return AttachmentEnrichment(item: withDetectedIdentifiers, detectedDOI: candidates.detectedDOI)
    }

    private func shouldAttemptDOIExtraction(for attachment: LocalAttachment) -> Bool {
        if attachment.contentType == "application/pdf" {
            return true
        }
        return attachment.localURL.pathExtension.lowercased() == "pdf"
    }

    private func resolveMetadataForPDFCandidates(_ candidates: PDFMetadataCandidates) async -> CanonicalMetadataRecord? {
        let arXivIdentifiers = candidates.identifiers.filter { $0.type == .arxiv }
        for arXiv in arXivIdentifiers {
            if let record = await resolveMetadata(
                identifiers: [Identifier(type: .arxiv, value: arXiv.value)],
                freeTextQuery: nil
            ) {
                return record
            }
        }

        let doiIdentifiers = candidates.identifiers.filter { $0.type == .doi }
        for doi in doiIdentifiers {
            if let record = await resolveMetadata(
                identifiers: [Identifier(type: .doi, value: doi.value)],
                freeTextQuery: nil
            ) {
                return record
            }
        }

        let isbnIdentifiers = candidates.identifiers.filter { $0.type == .isbn }
        for isbn in isbnIdentifiers {
            if let record = await resolveMetadata(
                identifiers: [Identifier(type: .isbn, value: isbn.value)],
                freeTextQuery: nil
            ) {
                return record
            }
        }

        for title in candidates.titleHints {
            if let record = await resolveMetadata(
                identifiers: [],
                freeTextQuery: title
            ) {
                return record
            }
        }

        return nil
    }

    private func resolveMetadata(
        identifiers: [Identifier],
        freeTextQuery: String?
    ) async -> CanonicalMetadataRecord? {
        let request = MetadataResolutionRequest(
            identifiers: identifiers,
            freeTextQuery: freeTextQuery
        )
        let result = await metadataRegistry.resolveAll(request)
        return result.bestMatch
    }

    private func mergeMetadata(_ record: CanonicalMetadataRecord, into item: BCItem, fallbackDOI: String?) -> BCItem {
        let fallbackIdentifiers: [Identifier]
        if let fallbackDOI {
            fallbackIdentifiers = [Identifier(type: .doi, value: fallbackDOI)]
        }
        else {
            fallbackIdentifiers = []
        }

        let mergedIdentifiers = mergeIdentifiers(record.identifiers + fallbackIdentifiers, into: item).identifiers
        let nextTitle = normalizedTitle(record.title) ?? normalizedTitle(item.title) ?? "Untitled Item"
        let cleanedRecordCreators = normalizedCreators(record.creators)
        let cleanedItemCreators = normalizedCreators(item.creators)
        let nextCreators = cleanedRecordCreators.isEmpty ? cleanedItemCreators : cleanedRecordCreators
        let nextType = record.itemType == .unknown ? item.itemType : record.itemType
        let nextYear = record.publicationYear ?? item.publicationYear

        return BCItem(
            id: item.id,
            title: nextTitle,
            identifiers: mergedIdentifiers,
            itemType: nextType,
            creators: nextCreators,
            publicationYear: nextYear,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }

    private func mergeIdentifiers(_ incoming: [Identifier], into item: BCItem) -> BCItem {
        var merged = item.identifiers
        var seen = Set<String>(merged.map(identifierDedupeKey(for:)))

        for identifier in incoming {
            var normalized = identifier
            if normalized.type == .doi {
                if let normalizedDOI = DOIParsing.normalizeCandidate(normalized.value) {
                    normalized.value = normalizedDOI
                } else {
                    continue
                }
            }

            normalized.value = normalized.value.bcCollapsedWhitespace()
            guard !normalized.value.isEmpty else {
                continue
            }

            let key = identifierDedupeKey(for: normalized)
            if seen.insert(key).inserted {
                merged.append(normalized)
            }
        }

        return BCItem(
            id: item.id,
            title: item.title,
            identifiers: merged,
            itemType: item.itemType,
            creators: item.creators,
            publicationYear: item.publicationYear,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }

    private func renderCitationPreviewForSelection() async {
        guard let selectedItem else {
            citationPreview = "Select an item to preview citation output"
            return
        }

        do {
            let cluster = CitationCluster(items: [CitationItem(itemID: selectedItem.id)])
            let style = CitationStyle(id: "apa", title: "APA")
            let output = try await citationFormatter.formatCluster(
                cluster,
                style: style,
                options: CitationRenderOptions(format: .plainText)
            )
            citationPreview = output.text
        }
        catch {
            citationPreview = "Citation preview failed: \(error.localizedDescription)"
        }
    }

    private func normalizedTitle(_ raw: String) -> String? {
        raw.bcTrimmedNonEmpty
    }

    private func normalizedCreators(_ creators: [Creator]) -> [Creator] {
        creators.compactMap { creator in
            let literal = creator.literalName?.bcTrimmedNonEmpty
            let given = creator.givenName?.bcTrimmedNonEmpty
            let family = creator.familyName?.bcTrimmedNonEmpty

            if literal == nil, given == nil, family == nil {
                return nil
            }

            return Creator(
                id: creator.id,
                givenName: given,
                familyName: family,
                literalName: literal
            )
        }
    }

    private func identifierDedupeKey(for identifier: Identifier) -> String {
        if identifier.type == .doi, let normalizedDOI = DOIParsing.normalizeCandidate(identifier.value) {
            return "\(identifier.type.rawValue):\(normalizedDOI.lowercased())"
        }
        return "\(identifier.type.rawValue):\(identifier.value.lowercased())"
    }
}
