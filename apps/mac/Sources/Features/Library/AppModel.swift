import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    // MARK: Lifecycle

    init(
        database: CitrationDatabase,
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
        ocrService: any OCRServicing = MistralOCRService(),
        openAlexAPIKeyStore: any APIKeyStore = InMemoryAPIKeyStore()
    ) {
        self.database = database
        self.store = store
        citation = CitationModel(formatter: citationFormatter)
        self.storageConnectors = storageConnectors
        self.sessionStore = sessionStore
        collections = CollectionsModel(store: collectionStore ?? AppModel.makeCollectionStore())
        notes = NotesModel(store: noteStore ?? AppModel.makeNoteStore())
        relationships = RelationshipsModel(store: relationshipStore ?? AppModel.makeRelationshipStore())
        importer = ImportModel(
            store: store,
            attachmentStore: attachmentStore ?? AppModel.makeAttachmentStore(),
            metadataRegistry: metadataRegistry,
            pdfDOIExtractor: pdfDOIExtractor,
            ocrService: ocrService
        )
        reader = ReaderModel(
            progressStore: readerProgressStore ?? AppModel.makeReaderProgressStore(),
            annotationStore: annotationStore ?? AppModel.makeAnnotationStore()
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

        Task {
            await setupAuthServices()
            await settings.refreshKeyStatus()
            await collections.refresh()
            await refreshItems()
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

    // Auth state
    var isSignedIn: Bool = false
    var currentUser: User?
    private(set) var authService: AuthService?
    private(set) var workspaceService: WorkspaceService?
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
    let store: any BCItemStore

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

    // MARK: Private

    private let sessionStore: AuthSessionStore

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
}
