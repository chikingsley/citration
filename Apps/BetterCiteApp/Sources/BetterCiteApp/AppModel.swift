import Foundation
import Observation
import BCStorage
import BCMetadataProviders
import BCCitationEngine
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

    var storageConnectors: [StorageConnector]

    private let store: any BCItemStore
    private let metadataRegistry: MetadataProviderRegistry
    private let citationFormatter: any CitationFormattingEngine

    init(
        store: any BCItemStore,
        metadataRegistry: MetadataProviderRegistry,
        citationFormatter: any CitationFormattingEngine,
        storageConnectors: [StorageConnector]
    ) {
        self.store = store
        self.metadataRegistry = metadataRegistry
        self.citationFormatter = citationFormatter
        self.storageConnectors = storageConnectors

        Task { await refreshItems() }
    }

    static func bootstrap() -> AppModel {
        let store = InMemoryItemStore()
        let providers: [any MetadataProvider] = [MockDOIMetadataProvider()]
        let metadataRegistry = MetadataProviderRegistry(providers: providers)
        let citationFormatter = StubCitationFormatter()
        let storageConnectors = [
            StorageConnector(name: "Local Files", type: .local, bucket: "local", isDefault: true)
        ]

        return AppModel(
            store: store,
            metadataRegistry: metadataRegistry,
            citationFormatter: citationFormatter,
            storageConnectors: storageConnectors
        )
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
