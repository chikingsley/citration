import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    // MARK: Lifecycle

    init(
        database: CitrationDatabase,
        connectionManager: ZoteroConnectionManager,
        store: any BCItemStore,
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
        openAlexAPIKeyStore: any APIKeyStore = InMemoryAPIKeyStore()
    ) {
        self.database = database
        self.connectionManager = connectionManager
        self.store = store
        self.annotationStore = annotationStore
        self.readerProgressStore = readerProgressStore
        citation = CitationModel(formatter: citationFormatter)
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
        reader = ReaderModel(
            progressStore: readerProgressStore,
            annotationStore: annotationStore
        )
        insights = InsightsModel(discoveryProvider: relatedWorkDiscoveryProvider)
        settings = OpenAlexSettingsModel(keyStore: openAlexAPIKeyStore)
        collections.bind(context: self)
        notes.bind(context: self)
        tags.bind(context: self)
        relationships.bind(context: self)
        reader.bind(context: self)
        citation.bind(context: self)
        insights.bind(context: self, relationships: relationships)
        settings.bind(context: self, insights: insights)
        importer.bind(context: self, collections: collections, reader: reader)

        startLibraryObservation()
        startNavigationObservation()

        Task {
            await settings.refreshKeyStatus()
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
    var items: [BCItem] = []
    var selectedItemID: UUID?
    var storageConnectors: [StorageConnector]
    var selectedWorkspaceTab: WorkspaceTab = .library
    private(set) var openDocuments: [LocalAttachment] = []
    private(set) var libraryObservationRevision = 0
    private(set) var navigationObservationRevision = 0
    private(set) var savedSearches: [ZoteroSavedSearchSummary] = []
    private(set) var deletedItemCount = 0

    let collections: CollectionsModel
    let notes: NotesModel
    let tags: TagsModel = .init()
    let relationships: RelationshipsModel
    let reader: ReaderModel
    let importer: ImportModel
    let citation: CitationModel
    let insights: InsightsModel
    let settings: OpenAlexSettingsModel
    let database: CitrationDatabase
    let connectionManager: ZoteroConnectionManager
    let store: any BCItemStore
    let annotationStore: any LibraryAnnotationStoring
    let readerProgressStore: any LibraryReaderProgressStoring

    var selectedItem: BCItem? {
        guard let selectedItemID else {
            return nil
        }
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
            selectedItemID = item.id
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
            for attachment in openDocuments where uniqueIDs.contains(attachment.itemID) {
                closeDocument(attachmentKey: attachment.objectKey)
            }
            for id in uniqueIDs {
                await store.removeItem(id: id)
            }
            await notes.removeItems(ids: uniqueIDs)
            await reader.removeItems(ids: uniqueIDs)
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
        if selectedItemID != id {
            notes.draft = ""
            citation.clearExport()
            relationships.clearSelectionDrafts()
            insights.clearForSelectionChange()
            importer.clearMetadataDiagnostics()
        }
        reader.clearIfSelectionChanged(to: id)
        selectedItemID = id
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
            selectedItemID = selectedID
            statusMessage = status
        }
    }

    func openDocument(_ attachment: LocalAttachment) {
        if let index = openDocuments.firstIndex(where: { $0.objectKey == attachment.objectKey }) {
            openDocuments[index] = attachment
        } else {
            openDocuments.append(attachment)
        }
        selectWorkspaceTab(.document(attachment.objectKey))
    }

    func selectWorkspaceTab(_ tab: WorkspaceTab) {
        switch tab {
        case .library:
            selectedWorkspaceTab = .library
            reader.clear()

        case let .document(attachmentKey):
            guard let attachment = openDocuments.first(where: { $0.objectKey == attachmentKey }) else {
                selectedWorkspaceTab = .library
                reader.clear()
                return
            }
            selectedWorkspaceTab = tab
            reader.open(attachment)
        }
    }

    func closeDocument(attachmentKey: String) {
        guard let index = openDocuments.firstIndex(where: { $0.objectKey == attachmentKey }) else {
            return
        }
        let wasSelected = selectedWorkspaceTab == .document(attachmentKey)
        openDocuments.remove(at: index)
        guard wasSelected else {
            return
        }
        if openDocuments.isEmpty {
            selectWorkspaceTab(.library)
        } else {
            let nextIndex = min(index, openDocuments.index(before: openDocuments.endIndex))
            selectWorkspaceTab(.document(openDocuments[nextIndex].objectKey))
        }
    }

    func makeReaderModel() -> ReaderModel {
        let model = ReaderModel(progressStore: readerProgressStore, annotationStore: annotationStore)
        model.bind(context: self)
        return model
    }

    // MARK: Private

    @ObservationIgnored private var libraryObservation: CitrationDatabaseObservation?
    @ObservationIgnored private var navigationObservation: CitrationDatabaseObservation?

    private func startLibraryObservation() {
        guard let store = store as? CitrationLibraryStore else {
            return
        }
        libraryObservation = database.observeLibraryItems(
            libraryID: store.libraryID,
            onError: { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Failed to observe library changes"
                }
            },
            onChange: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    libraryObservationRevision += 1
                    await collections.refresh()
                    await refreshItems()
                }
            }
        )
    }

    private func startNavigationObservation() {
        guard let store = store as? CitrationLibraryStore else {
            return
        }
        navigationObservation = database.observeLibraryNavigation(
            libraryID: store.libraryID,
            onError: { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Failed to observe library navigation"
                }
            },
            onChange: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    savedSearches = snapshot.savedSearches
                    deletedItemCount = snapshot.deletedItemCount
                    navigationObservationRevision += 1
                }
            }
        )
    }
}
