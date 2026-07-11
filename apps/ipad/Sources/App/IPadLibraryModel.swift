import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class IPadLibraryModel {
    // MARK: Lifecycle

    init(
        database: CitrationDatabase,
        store: CitrationLibraryStore,
        connectionManager: ZoteroConnectionManager
    ) {
        self.database = database
        self.store = store
        self.connectionManager = connectionManager
    }

    // MARK: Internal

    struct OpenDocument: Identifiable {
        let item: SynchronizedLibraryItem
        let record: ZoteroAttachmentCacheRecord
        let url: URL

        var id: String {
            record.itemKey
        }
    }

    enum Source: Hashable {
        case allItems
        case collection(UUID)
        case tag(String)
    }

    var items: [SynchronizedLibraryItem] = []
    var collections: LibraryCollectionSnapshot = .init()
    var selectedSource: Source? = .allItems
    var selectedItemIdentity: SynchronizedLibraryItemIdentity?
    var attachmentRecords: [ZoteroAttachmentCacheRecord] = []
    var selectedNotes: [SynchronizedLibraryNote] = []
    var searchText = ""
    var searchResultKeys: Set<String> = []
    var configuration: ZoteroConnectionConfiguration = .localOnly
    var syncStatus: ZoteroSyncStatusSnapshot?
    var statusMessage = "Ready"
    var isWorking = false
    var settingsPresented = false
    var openDocument: OpenDocument?
    var readerAnnotations: [SynchronizedLibraryAnnotation] = []
    var readerProgress: ReaderProgress?
    var recoveringFailureIDs: Set<Int64> = []

    let database: CitrationDatabase
    let store: CitrationLibraryStore
    let connectionManager: ZoteroConnectionManager

    var selectedItem: SynchronizedLibraryItem? {
        guard let selectedItemIdentity else {
            return nil
        }
        return items.first { $0.identity == selectedItemIdentity }
    }

    var availableTags: [String] {
        Set(items.flatMap(\.tags)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var visibleItems: [SynchronizedLibraryItem] {
        let sourceItems = switch selectedSource ?? .allItems {
        case .allItems:
            items
        case let .collection(collectionID):
            collectionItems(collectionID: collectionID)
        case let .tag(tag):
            items.filter { item in
                item.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return sourceItems
        }
        return sourceItems.filter { searchResultKeys.contains($0.identity.objectKey) }
    }

    static func bootstrap() -> IPadLibraryModel {
        do {
            let applicationDirectory = try CitrationCorePaths.applicationSupportDirectory()
            let database = try CitrationDatabase(at: applicationDirectory.appending(path: "library.sqlite"))
            let profile = try database.loadZoteroConnectionProfile()
            let attachmentsDirectory = applicationDirectory.appending(path: "attachments", directoryHint: .isDirectory)
            let store = try CitrationLibraryStore(
                database: database,
                attachmentsDirectory: attachmentsDirectory,
                libraryIdentity: profile?.libraryIdentity ?? .init(type: "local", remoteID: 0),
                libraryName: profile?.displayName ?? "Local Library"
            )
            let connectionManager = ZoteroConnectionManager(
                database: database,
                credentialStore: FileZoteroCredentialStore(),
                attachmentsDirectory: attachmentsDirectory
            )
            return IPadLibraryModel(database: database, store: store, connectionManager: connectionManager)
        } catch {
            fatalError("Failed to initialize the iPad library: \(error)")
        }
    }

    func start() async {
        await reloadAll()
        startObserving()
    }

    func reloadAll() async {
        items = await store.listLibraryItems()
        collections = await (try? store.snapshot()) ?? .init()
        configuration = await (try? connectionManager.configuration()) ?? .localOnly
        let libraryID = await store.selectedLibraryID()
        syncStatus = try? database.syncStatusSnapshot(libraryID: libraryID)
        await refreshAttachments()
    }

    func selectItem(_ identity: SynchronizedLibraryItemIdentity?) {
        selectedItemIdentity = identity
        Task { await refreshSelection() }
    }

    func open(item: SynchronizedLibraryItem, record: ZoteroAttachmentCacheRecord, url: URL) {
        readerAnnotations = []
        readerProgress = nil
        openDocument = OpenDocument(item: item, record: record, url: url)
    }

    func updateSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResultKeys = []
            return
        }
        let database = database
        Task {
            do {
                let libraryID = await store.selectedLibraryID()
                let keys = try database.searchLibraryItemKeys(libraryID: libraryID, query: query)
                guard !Task.isCancelled else {
                    return
                }
                searchResultKeys = Set(keys)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                searchResultKeys = []
                statusMessage = "Search failed"
            }
        }
    }

    func refreshAttachments() async {
        await refreshSelection()
    }

    func refreshSelection() async {
        guard let selectedItem else {
            attachmentRecords = []
            selectedNotes = []
            return
        }
        attachmentRecords = (try? database.attachmentCacheRecords(
            libraryID: selectedItem.identity.libraryID,
            parentItemKey: selectedItem.identity.objectKey
        )) ?? []
        selectedNotes = await (try? store.listSynchronizedNotes(itemID: selectedItem.identity.appUUID)) ?? []
    }

    // MARK: Private

    private var searchTask: Task<Void, Never>?
    private var itemObservation: CitrationDatabaseObservation?
    private var syncObservation: CitrationDatabaseObservation?

    private func collectionItems(collectionID: UUID) -> [SynchronizedLibraryItem] {
        let itemIDs = Set(
            collections.memberships
                .filter { $0.collectionID == collectionID }
                .map(\.itemID)
        )
        return items.filter { itemIDs.contains($0.identity.appUUID) }
    }

    private func startObserving() {
        itemObservation?.cancel()
        syncObservation?.cancel()
        Task {
            let libraryID = await store.selectedLibraryID()
            itemObservation = database.observeLibraryItems(
                libraryID: libraryID,
                onError: { _ in },
                onChange: { [weak self] _ in
                    Task { @MainActor in
                        await self?.reloadAll()
                    }
                }
            )
            syncObservation = database.observeSyncStatus(
                libraryID: libraryID,
                onError: { _ in },
                onChange: { [weak self] status in
                    Task { @MainActor in
                        self?.syncStatus = status
                    }
                }
            )
        }
    }
}
