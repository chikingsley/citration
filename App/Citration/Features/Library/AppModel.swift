import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    // MARK: Lifecycle

    init(
        store: any BCItemStore,
        metadataRegistry: MetadataProviderRegistry,
        citationFormatter: any CitationFormattingEngine,
        storageConnectors: [StorageConnector],
        sessionStore: AuthSessionStore = InMemoryAuthSessionStore(),
        pdfDOIExtractor: any PDFDOIExtracting = NullPDFDOIExtractor(),
        attachmentStore: LocalAttachmentStore? = nil,
        annotationStore: LocalAnnotationStore? = nil,
        collectionStore: LocalCollectionStore? = nil,
        noteStore: LocalNoteStore? = nil,
        relationshipStore: LocalRelationshipStore? = nil,
        readerProgressStore: LocalReaderProgressStore? = nil,
        relatedWorkDiscoveryProvider: any RelatedWorkDiscoveryProvider = NoopRelatedWorkDiscoveryProvider(),
        openAlexAPIKeyStore: any OpenAlexAPIKeyStore = InMemoryOpenAlexAPIKeyStore()
    ) {
        self.store = store
        self.metadataRegistry = metadataRegistry
        self.citationFormatter = citationFormatter
        self.storageConnectors = storageConnectors
        self.sessionStore = sessionStore
        self.attachmentStore = attachmentStore ?? AppModel.makeAttachmentStore()
        self.annotationStore = annotationStore ?? AppModel.makeAnnotationStore()
        collections = CollectionsModel(store: collectionStore ?? AppModel.makeCollectionStore())
        notes = NotesModel(store: noteStore ?? AppModel.makeNoteStore())
        self.relationshipStore = relationshipStore ?? AppModel.makeRelationshipStore()
        self.readerProgressStore = readerProgressStore ?? AppModel.makeReaderProgressStore()
        self.pdfDOIExtractor = pdfDOIExtractor
        self.relatedWorkDiscoveryProvider = relatedWorkDiscoveryProvider
        self.openAlexAPIKeyStore = openAlexAPIKeyStore
        collections.bind(context: self)
        notes.bind(context: self)
        tags.bind(context: self)

        Task {
            await setupAuthServices()
            await refreshOpenAlexAPIKeyStatus()
            await collections.refresh()
            await refreshItems()
            await refreshRelationships()
            await notes.refreshForSelection()
        }
    }

    // MARK: Internal

    var route: Route = .workspace
    var doiInput: String = ""
    var isResolvingDOI: Bool = false
    var isImportingAttachments: Bool = false
    var reprocessingItemID: UUID?
    var statusMessage: String = "Ready"
    var metadataWarnings: [String] = []
    var metadataConflicts: [MetadataResolutionConflict] = []
    var items: [BCItem] = []
    var selectedItemID: UUID?
    var citationPreview: String = "Select an item to preview citation output"
    var citationExportFormat: CitationExportFormat = .cslJSON
    var citationExportText: String = ""
    var selectedItemAttachments: [LocalAttachment] = []
    var activeReaderAttachment: LocalAttachment?
    var activeReaderProgress: ReaderProgress?
    var activeReaderAnnotations: [LibraryAnnotation] = []
    var readerNoteDraft: String = ""
    var libraryRelationships: [LibraryRelationship] = []
    var selectedItemRelationships: [LibraryRelationship] = []
    var selectedItemDiscoverySuggestions: [WorkDiscoverySuggestion] = []
    var isLoadingDiscoverySuggestions: Bool = false
    var openAlexAPIKeyDraft: String = ""
    var hasOpenAlexAPIKey: Bool = false
    var isSavingOpenAlexAPIKey: Bool = false
    var relatedItemTargetID: UUID?
    var relatedItemKind: LibraryRelationshipKind = .userLinked
    var relatedItemNoteDraft: String = ""
    var storageConnectors: [StorageConnector]

    // Auth state
    var isSignedIn: Bool = false
    var currentUser: User?
    private(set) var authService: AuthService?
    private(set) var workspaceService: WorkspaceService?
    let collections: CollectionsModel
    let notes: NotesModel
    let tags: TagsModel = .init()
    let store: any BCItemStore
    let metadataRegistry: MetadataProviderRegistry
    let attachmentStore: LocalAttachmentStore
    let annotationStore: LocalAnnotationStore
    let relationshipStore: LocalRelationshipStore
    let readerProgressStore: LocalReaderProgressStore
    let pdfDOIExtractor: any PDFDOIExtracting
    let relatedWorkDiscoveryProvider: any RelatedWorkDiscoveryProvider
    let openAlexAPIKeyStore: any OpenAlexAPIKeyStore

    var isReprocessingAttachments: Bool {
        reprocessingItemID != nil
    }

    var hasMetadataDiagnostics: Bool {
        !metadataWarnings.isEmpty || !metadataConflicts.isEmpty
    }

    var selectedItem: BCItem? {
        guard let selectedItemID else {
            return nil
        }
        return items.first { $0.id == selectedItemID }
    }

    func signInWithApple(identityToken: String) async throws {
        guard let authService else {
            return
        }
        _ = try await authService.signInWithApple(identityToken: identityToken)
        isSignedIn = true
        currentUser = try? await authService.currentUser()
    }

    func signOut() async {
        guard let authService else {
            return
        }
        try? await authService.signOut()
        isSignedIn = false
        currentUser = nil
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
        await notes.refreshForSelection()
        refreshSelectedItemRelationships()
        await refreshSelectedItemDiscoverySuggestions()
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
            for id in uniqueIDs {
                await store.removeItem(id: id)
            }
            await notes.removeItems(ids: uniqueIDs)
            try? await relationshipStore.removeRelationships(itemIDs: uniqueIDs)
            try? await readerProgressStore.removeProgress(itemIDs: uniqueIDs)
            await collections.removeItems(ids: uniqueIDs)
            await refreshRelationships()
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
            citationExportText = ""
            relatedItemTargetID = nil
            relatedItemNoteDraft = ""
            selectedItemDiscoverySuggestions = []
            clearMetadataDiagnostics()
        }
        if activeReaderAttachment?.itemID != id {
            activeReaderAttachment = nil
            activeReaderProgress = nil
            activeReaderAnnotations = []
            readerNoteDraft = ""
        }
        selectedItemID = id
        Task {
            await renderCitationPreviewForSelection()
            await refreshSelectedItemAttachments()
            collections.refreshSelectedItemMemberships()
            await notes.refreshForSelection()
            refreshSelectedItemRelationships()
            await refreshSelectedItemDiscoverySuggestions()
        }
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

    // MARK: Private

    private let sessionStore: AuthSessionStore

    private let citationFormatter: any CitationFormattingEngine

    // MARK: - Auth

    private func setupAuthServices() async {
        guard let environment = try? SaaSEnvironment(rootDomain: "citration.app") else {
            return
        }

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
        } catch {
            citationPreview = "Citation preview failed: \(error.localizedDescription)"
        }
    }
}
