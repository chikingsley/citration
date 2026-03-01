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

    var route: Route = .workspace
    var doiInput: String = ""
    var isResolvingDOI: Bool = false
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

    init(
        store: any BCItemStore,
        metadataRegistry: MetadataProviderRegistry,
        citationFormatter: any CitationFormattingEngine,
        storageConnectors: [StorageConnector],
        sessionStore: AuthSessionStore = InMemoryAuthSessionStore()
    ) {
        self.store = store
        self.metadataRegistry = metadataRegistry
        self.citationFormatter = citationFormatter
        self.storageConnectors = storageConnectors
        self.sessionStore = sessionStore
        self.attachmentStore = AppModel.makeAttachmentStore()

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

        let providers: [any MetadataProvider] = [MockDOIMetadataProvider()]
        let metadataRegistry = MetadataProviderRegistry(providers: providers)
        let citationFormatter = StubCitationFormatter()
        let storageConnectors = [
            StorageConnector(name: "Local Files", type: .local, bucket: "local", isDefault: true)
        ]
        let sessionStore = KeychainAuthSessionStore()

        return AppModel(
            store: store,
            metadataRegistry: metadataRegistry,
            citationFormatter: citationFormatter,
            storageConnectors: storageConnectors,
            sessionStore: sessionStore
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
        let doi = doiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !doi.isEmpty else {
            statusMessage = "Enter a DOI first"
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
                title: best.title,
                identifiers: best.identifiers,
                itemType: best.itemType,
                creators: best.creators,
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

        Task {
            await store.removeItem(id: selectedItemID)
            await refreshItems()
            statusMessage = "Removed item"
        }
    }

    func selectItem(id: UUID?) {
        selectedItemID = id
        Task {
            await renderCitationPreviewForSelection()
            await refreshSelectedItemAttachments()
        }
    }

    func importAttachments(urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            statusMessage = "No valid files to import"
            return
        }

        Task {
            var importedCount = 0
            var failedFiles = [String]()

            if let selectedItem {
                for url in fileURLs {
                    do {
                        _ = try await attachmentStore.importFile(from: url, for: selectedItem)
                        importedCount += 1
                    }
                    catch {
                        failedFiles.append(url.lastPathComponent)
                    }
                }
            } else {
                for url in fileURLs {
                    do {
                        let title = inferredTitle(from: url)
                        let item = BCItem(title: title)
                        await store.upsert(item)
                        _ = try await attachmentStore.importFile(from: url, for: item)
                        selectedItemID = item.id
                        importedCount += 1
                    }
                    catch {
                        failedFiles.append(url.lastPathComponent)
                    }
                }
            }

            await refreshItems()

            if importedCount > 0, failedFiles.isEmpty {
                let noun = importedCount == 1 ? "file" : "files"
                statusMessage = "Imported \(importedCount) \(noun)"
            } else if importedCount > 0 {
                statusMessage = "Imported \(importedCount), failed \(failedFiles.count)"
            } else {
                statusMessage = "Import failed"
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
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
}
