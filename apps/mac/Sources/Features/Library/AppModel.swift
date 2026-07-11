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
        annotationStore: any LibraryAnnotationStoring,
        collectionStore: any LibraryCollectionStoring,
        noteStore: any LibraryNoteStoring,
        relationshipStore: any LibraryRelationshipStoring,
        readerProgressStore: any LibraryReaderProgressStoring,
        pdfDOIExtractor: any PDFDOIExtracting = NullPDFDOIExtractor(),
        relatedWorkDiscoveryProvider: any RelatedWorkDiscoveryProvider = NoopRelatedWorkDiscoveryProvider(),
        ocrService: any OCRServicing = MistralOCRService(),
        openAlexAPIKeyStore: any APIKeyStore = InMemoryAPIKeyStore(),
        ocrAPIKeyStore: any APIKeyStore = InMemoryAPIKeyStore()
    ) {
        self.database = database
        self.connectionManager = connectionManager
        self.store = store
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
    var storageConnectors: [StorageConnector]
    var selectedWorkspaceTab: WorkspaceTab = .library
    private(set) var documentSessions: [DocumentSession] = []
    var libraryObservationRevision = 0
    var navigationObservationRevision = 0
    var savedSearches: [ZoteroSavedSearchSummary] = []
    var deletedItemCount = 0
    var syncStatus: ZoteroSyncStatusSnapshot?

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
    let connectionManager: ZoteroConnectionManager
    let store: any SynchronizedLibraryItemStoring
    let annotationStore: any LibraryAnnotationStoring
    let readerProgressStore: any LibraryReaderProgressStoring

    // MARK: Observation

    @ObservationIgnored var libraryObservation: CitrationDatabaseObservation?
    @ObservationIgnored var navigationObservation: CitrationDatabaseObservation?
    @ObservationIgnored var syncStatusObservation: CitrationDatabaseObservation?
    @ObservationIgnored var observedLibraryID: Int64?

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
            selectedItemIdentity = newValue.flatMap { appUUID in
                items.first { $0.identity.appUUID == appUUID }?.identity
            }
        }
    }

    var selectedLibraryItem: SynchronizedLibraryItem? {
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
        let hasValidSelection = selectedItemIdentity.map { selectedIdentity in
            items.contains { $0.identity == selectedIdentity }
        } ?? false
        if !hasValidSelection {
            selectedItemIdentity = items.first?.identity
        }
        await citation.renderPreviewForSelection()
        await importer.refreshSelectedItemAttachments()
        await notes.refreshForSelection()
        relationships.refreshForSelection()
        await insights.refreshForSelection()
    }

    func addEmptyItem() {
        Task {
            let item = BCItem(title: "Untitled Item")
            await store.upsert(item)
            await refreshItems()
            selectedItemIdentity = items.first { $0.identity.appUUID == item.id }?.identity
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

    func selectItem(id: UUID?) {
        selectItem(identity: id.flatMap { appUUID in
            items.first { $0.identity.appUUID == appUUID }?.identity
        })
    }

    func selectItem(identity: SynchronizedLibraryItemIdentity?) {
        if selectedItemIdentity != identity {
            notes.draft = ""
            citation.clearExport()
            relationships.clearSelectionDrafts()
            insights.clearForSelectionChange()
            importer.clearMetadataDiagnostics()
        }
        libraryReader.clearIfSelectionChanged(to: identity?.appUUID)
        selectedItemIdentity = identity
        Task {
            await citation.renderPreviewForSelection()
            await importer.refreshSelectedItemAttachments()
            collections.refreshSelectedItemMemberships()
            await notes.refreshForSelection()
            relationships.refreshForSelection()
            await insights.refreshForSelection()
        }
    }

    func refreshLibrary() async {
        await refreshItems()
    }

    func addItem(_ item: BCItem) async {
        await store.upsert(item)
        await refreshItems()
    }

    func persistItem(_ item: BCItem, status: String) {
        let selectedID = item.id
        Task { @MainActor in
            await store.upsert(item)
            await refreshItems()
            selectedItemIdentity = items.first { $0.identity.appUUID == selectedID }?.identity
            statusMessage = status
        }
    }

    func openDocument(_ attachment: LocalAttachment) {
        if let index = documentSessions.firstIndex(where: { $0.id == attachment.objectKey }) {
            documentSessions[index].attachment = attachment
        } else {
            let reader = makeReaderModel()
            reader.open(attachment)
            documentSessions.append(DocumentSession(attachment: attachment, reader: reader))
        }
        selectWorkspaceTab(.document(attachment.objectKey))
    }

    func selectWorkspaceTab(_ tab: WorkspaceTab) {
        switch tab {
        case .library:
            selectedWorkspaceTab = .library

        case let .document(attachmentKey):
            guard let session = documentSessions.first(where: { $0.id == attachmentKey }) else {
                selectedWorkspaceTab = .library
                return
            }
            selectedWorkspaceTab = tab
            session.reader.open(session.attachment)
        }
    }

    func closeDocument(attachmentKey: String) {
        guard let index = documentSessions.firstIndex(where: { $0.id == attachmentKey }) else {
            return
        }
        let wasSelected = selectedWorkspaceTab == .document(attachmentKey)
        let removed = documentSessions.remove(at: index)
        removed.reader.clear()
        guard wasSelected else {
            return
        }
        if documentSessions.isEmpty {
            selectWorkspaceTab(.library)
        } else {
            let nextIndex = min(index, documentSessions.index(before: documentSessions.endIndex))
            selectWorkspaceTab(.document(documentSessions[nextIndex].id))
        }
    }

    func closeAllDocuments() {
        let keys = documentSessions.map(\.id)
        for key in keys {
            closeDocument(attachmentKey: key)
        }
        selectedWorkspaceTab = .library
    }

    func handleAttachmentRemoved(_ attachment: LocalAttachment) async {
        if let session = documentSessions.first(where: { $0.id == attachment.objectKey }) {
            await session.reader.handleAttachmentRemoved(attachment)
            closeDocument(attachmentKey: attachment.objectKey)
        } else {
            await libraryReader.handleAttachmentRemoved(attachment)
        }
    }

    func reconcileOpenDocuments(itemID: UUID, availableAttachments: [LocalAttachment]) {
        let availableKeys = Set(availableAttachments.map(\.objectKey))
        let missingKeys = documentSessions
            .filter { $0.attachment.itemID == itemID && !availableKeys.contains($0.id) }
            .map(\.id)
        for key in missingKeys {
            closeDocument(attachmentKey: key)
        }
    }

    func makeReaderModel() -> ReaderModel {
        let model = ReaderModel(progressStore: readerProgressStore, annotationStore: annotationStore)
        model.bind(context: self)
        return model
    }

    // MARK: Private

    @ObservationIgnored private let libraryReader: ReaderModel
}
