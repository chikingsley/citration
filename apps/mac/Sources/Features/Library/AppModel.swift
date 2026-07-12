import CitrationCore
import Foundation
import Observation

// MARK: - AppModel

@MainActor
@Observable
final class AppModel {
    // MARK: Lifecycle

    init(
        database: CitrationDatabase,
        connectionManager: ZoteroConnectionManager,
        store: any SynchronizedLibraryItemStoring,
        metadataRegistry: MetadataProviderRegistry,
        citationFormatter: any CitationFormattingEngine,
        storageConnectors: [StorageConnector],
        attachmentStore: any LibraryAttachmentStoring,
        annotationStore: any SynchronizedLibraryAnnotationStoring,
        collectionStore: any LibraryCollectionStoring,
        noteStore: any SynchronizedLibraryNoteStoring,
        relationshipStore: any LibraryRelationshipStoring,
        readerProgressStore: any LibraryReaderProgressStoring,
        pdfDOIExtractor: any PDFDOIExtracting,
        relatedWorkDiscoveryProvider: any RelatedWorkDiscoveryProvider,
        ocrService: any OCRServicing = MistralOCRService(),
        openAlexAPIKeyStore: any APIKeyStore,
        ocrAPIKeyStore: any APIKeyStore
    ) {
        self.database = database
        self.connectionManager = connectionManager
        automaticSyncCoordinator = ForegroundSyncCoordinator(connectionManager: connectionManager)
        self.store = store
        self.attachmentStore = attachmentStore
        observedLibraryID = (store as? CitrationLibraryStore)?.initialLibraryID
        self.annotationStore = annotationStore
        self.readerProgressStore = readerProgressStore
        citation = CitationModel(formatter: citationFormatter)
        zoteroSettings = ZoteroSettingsModel(connectionManager: connectionManager)
        ocrSettings = OCRSettingsModel(keyStore: ocrAPIKeyStore)
        self.storageConnectors = storageConnectors
        collections = CollectionsModel(store: collectionStore)
        notes = NotesModel(store: noteStore)
        relationships = RelationshipsModel(store: relationshipStore)
        importer = ImportModel(
            store: store,
            attachmentStore: attachmentStore,
            metadataRegistry: metadataRegistry,
            pdfDOIExtractor: pdfDOIExtractor,
            ocrService: ocrService
        )
        libraryReader = ReaderModel(
            progressStore: readerProgressStore,
            annotationStore: annotationStore
        )
        insights = InsightsModel(discoveryProvider: relatedWorkDiscoveryProvider)
        openAlexSettings = OpenAlexSettingsModel(keyStore: openAlexAPIKeyStore)
        collections.bind(context: self)
        notes.bind(context: self)
        tags.bind(context: self)
        relationships.bind(context: self)
        libraryReader.bind(context: self)
        citation.bind(context: self)
        insights.bind(context: self, relationships: relationships)
        zoteroSettings.bind(context: self)
        ocrSettings.bind(context: self)
        openAlexSettings.bind(context: self, insights: insights)
        importer.bind(context: self, collections: collections)

        startLibraryObservation()
        startNavigationObservation()
        startSyncStatusObservation()

        Task {
            await zoteroSettings.refresh()
            await startAutomaticSynchronization()
            await ocrSettings.refreshKeyStatus()
            await openAlexSettings.refreshKeyStatus()
            await collections.refresh()
            if libraryObservation == nil {
                await refreshItems()
            }
            await relationships.refresh()
            await notes.refreshForSelection()
        }
    }

    // MARK: Internal

    var route: Route = .workspace
    var statusMessage: String = "Ready"
    var items: [SynchronizedLibraryItem] = []
    var selectedItemIdentity: SynchronizedLibraryItemIdentity?
    var selectedLibraryItemDetail: SynchronizedLibraryItem?
    var storageConnectors: [StorageConnector]
    var selectedWorkspaceTab: WorkspaceTab = .library
    var documentSessions: [DocumentSession] = []
    var libraryObservationRevision = 0
    var navigationObservationRevision = 0
    var savedSearches: [ZoteroSavedSearchSummary] = []
    var deletedItemCount = 0
    var syncStatus: ZoteroSyncStatusSnapshot?
    var selectedAttachmentCacheRecords: [ZoteroAttachmentCacheRecord] = []
    var syncRecoveryOperationIDs: Set<Int64> = []
    var attachmentDownloadKeys: Set<String> = []
    var attachmentDownloadProgressByItemID: [UUID: Double] = [:]
    var itemTypeDefinitions: [ZoteroItemTypeDefinition] = []
    var itemEditingSchemas: [String: ZoteroItemEditingSchema] = [:]
    var pendingReadableAttachmentChoices: [ReadableAttachmentChoice] = []

    let collections: CollectionsModel
    let notes: NotesModel
    let tags: TagsModel = .init()
    let relationships: RelationshipsModel
    let importer: ImportModel
    let citation: CitationModel
    let insights: InsightsModel
    let zoteroSettings: ZoteroSettingsModel
    let ocrSettings: OCRSettingsModel
    let openAlexSettings: OpenAlexSettingsModel
    let database: CitrationDatabase
    let automaticSyncCoordinator: ForegroundSyncCoordinator
    let connectionManager: ZoteroConnectionManager
    let store: any SynchronizedLibraryItemStoring
    let attachmentStore: any LibraryAttachmentStoring
    let annotationStore: any SynchronizedLibraryAnnotationStoring
    let readerProgressStore: any LibraryReaderProgressStoring

    // MARK: Observation

    @ObservationIgnored var libraryObservation: CitrationDatabaseObservation?
    @ObservationIgnored var navigationObservation: CitrationDatabaseObservation?
    @ObservationIgnored var syncStatusObservation: CitrationDatabaseObservation?
    @ObservationIgnored var observedLibraryID: Int64?
    @ObservationIgnored var selectionRefreshTask: Task<Void, Never>?
    @ObservationIgnored var itemDetailCache: [SynchronizedLibraryItemIdentity: SynchronizedLibraryItem] = [:]
    @ObservationIgnored var itemDetailCacheOrder: [SynchronizedLibraryItemIdentity] = []

    @ObservationIgnored let libraryReader: ReaderModel

    var openDocuments: [LocalAttachment] {
        documentSessions.map(\.attachment)
    }

    var reader: ReaderModel {
        guard case let .document(attachmentKey) = selectedWorkspaceTab else {
            return libraryReader
        }
        return documentSessions.first { $0.id == attachmentKey }?.reader ?? libraryReader
    }

    var bibliographicItems: [BCItem] {
        items.map(\.bibliographic)
    }

    var selectedItemID: UUID? {
        get {
            selectedItemIdentity?.appUUID
        }
        set {
            selectItem(identity: newValue.flatMap { appUUID in
                items.first { $0.identity.appUUID == appUUID }?.identity
            })
        }
    }

    var selectedLibraryItem: SynchronizedLibraryItem? {
        guard let selectedItemIdentity else {
            return nil
        }
        if selectedLibraryItemDetail?.identity == selectedItemIdentity {
            return selectedLibraryItemDetail
        }
        return items.first { $0.identity == selectedItemIdentity }
    }

    var selectedLibraryItemSummary: SynchronizedLibraryItem? {
        guard let selectedItemIdentity else {
            return nil
        }
        return items.first { $0.identity == selectedItemIdentity }
    }

    var selectedItem: BCItem? {
        selectedLibraryItem?.bibliographic
    }

    func refreshItems() async {
        items = await store.listLibraryItems()
        pruneItemDetailCache(validIdentities: Set(items.map(\.identity)))
        let hasValidSelection = selectedItemIdentity.map { selectedIdentity in
            items.contains { $0.identity == selectedIdentity }
        } ?? false
        if !hasValidSelection {
            selectItem(identity: items.first?.identity)
        } else {
            refreshSelectionAfterLibraryReload()
        }
    }

    func addEmptyItem() {
        Task {
            let item = BCItem(title: "Untitled Item")
            await store.upsert(item)
            await refreshItems()
            selectItem(identity: items.first { $0.identity.appUUID == item.id }?.identity)
            statusMessage = "Added: \(item.title)"
        }
    }

    func removeSelectedItem() {
        guard let selectedItemID else {
            return
        }

        removeItems(ids: [selectedItemID])
    }

    func removeItems(ids: [UUID]) {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else {
            return
        }

        Task { @MainActor in
            for session in documentSessions where uniqueIDs.contains(session.attachment.itemID) {
                closeDocument(attachmentKey: session.id)
            }
            for id in uniqueIDs {
                await store.removeItem(id: id)
            }
            await notes.removeItems(ids: uniqueIDs)
            await libraryReader.removeItems(ids: uniqueIDs)
            await collections.removeItems(ids: uniqueIDs)
            await relationships.removeItems(ids: uniqueIDs)
            await refreshItems()

            if uniqueIDs.count == 1 {
                statusMessage = "Removed item"
            } else {
                statusMessage = "Removed \(uniqueIDs.count) items"
            }
        }
    }

    func refreshLibrary() async {
        await refreshItems()
    }

    func searchLibraryItemKeys(query: String, field: LibrarySearchField) async -> [String] {
        guard let observedLibraryID else {
            return []
        }
        let database = database
        let keys = await Task.detached {
            try? database.searchLibraryItemKeys(
                libraryID: observedLibraryID,
                query: query,
                field: field
            )
        }.value
        guard let keys else {
            statusMessage = "Search failed"
            return []
        }
        return keys
    }

    func addItem(_ item: BCItem) async {
        await store.upsert(item)
        await refreshItems()
    }

    func persistItem(_ item: BCItem, status: String) {
        let selectedID = item.id
        Task { @MainActor in
            await store.upsert(item)
            statusMessage = status
            await refreshItems()
            selectItem(identity: items.first { $0.identity.appUUID == selectedID }?.identity)
        }
    }

    func updateItemFields(
        identity: SynchronizedLibraryItemIdentity,
        updates: [ZoteroItemFieldUpdate]
    ) async throws -> SynchronizedLibraryItem {
        let summary = try await store.updateItemFields(identity: identity, updates: updates)
        await refreshItems()
        let updated = await hydrateItemDetail(summary)
        installItemDetail(updated)
        selectItem(identity: identity)
        statusMessage = "Updated item"
        return updated
    }
}
