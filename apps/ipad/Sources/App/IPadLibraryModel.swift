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
    var pendingDocumentChoices: [ZoteroAttachmentCacheRecord] = []
    var openingItemIdentity: SynchronizedLibraryItemIdentity?
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
        selectionTask?.cancel()
        selectedItemIdentity = identity
        pendingDocumentChoices = []
        guard let identity else {
            openingItemIdentity = nil
            attachmentRecords = []
            selectedNotes = []
            return
        }
        openingItemIdentity = identity
        selectionTask = Task {
            await refreshSelection()
            guard !Task.isCancelled, selectedItemIdentity == identity else {
                return
            }
            await openPreferredDocumentForSelection()
            if selectedItemIdentity == identity {
                openingItemIdentity = nil
            }
        }
    }

    func open(item: SynchronizedLibraryItem, record: ZoteroAttachmentCacheRecord, url: URL) {
        readerAnnotations = []
        readerProgress = nil
        openDocument = OpenDocument(item: item, record: record, url: url)
    }

    func openDocumentChoice(_ record: ZoteroAttachmentCacheRecord) {
        pendingDocumentChoices = []
        guard let item = selectedItem else {
            return
        }
        openingItemIdentity = item.identity
        Task {
            await openOrDownload(record, for: item)
            if selectedItemIdentity == item.identity {
                openingItemIdentity = nil
            }
        }
    }

    func dismissDocumentChoices() {
        pendingDocumentChoices = []
        openingItemIdentity = nil
    }

    func closeDocument() {
        openDocument = nil
        readerAnnotations = []
        readerProgress = nil
        statusMessage = "Ready"
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

    func openPreferredDocumentForSelection() async {
        guard let item = selectedItem else {
            return
        }
        let readable = attachmentRecords
            .filter { DocumentFormat.infer(fileName: $0.filename, contentType: $0.contentType).isSupportedInApp }
            .sorted(by: compareReadableAttachments)
        switch readable.count {
        case 0:
            statusMessage = "No readable document attached"

        case 1:
            if let record = readable.first {
                await openOrDownload(record, for: item)
            }

        default:
            pendingDocumentChoices = readable
        }
    }

    // MARK: Private

    private var searchTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
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

    private func openOrDownload(
        _ record: ZoteroAttachmentCacheRecord,
        for item: SynchronizedLibraryItem
    ) async {
        if
            let url = record.localURL,
            FileManager.default.fileExists(atPath: url.path)
        {
            open(item: item, record: record, url: url)
            return
        }
        await download(record)
        guard
            selectedItemIdentity == item.identity,
            let refreshed = attachmentRecords.first(where: { $0.itemKey == record.itemKey }),
            let url = refreshed.localURL,
            FileManager.default.fileExists(atPath: url.path)
        else {
            return
        }
        open(item: item, record: refreshed, url: url)
    }

    private func compareReadableAttachments(
        _ lhs: ZoteroAttachmentCacheRecord,
        _ rhs: ZoteroAttachmentCacheRecord
    ) -> Bool {
        let leftFormat = DocumentFormat.infer(fileName: lhs.filename, contentType: lhs.contentType)
        let rightFormat = DocumentFormat.infer(fileName: rhs.filename, contentType: rhs.contentType)
        let priority: [DocumentFormat: Int] = [.pdf: 0, .epub: 1, .html: 2, .plainText: 3]
        let left = priority[leftFormat] ?? Int.max
        let right = priority[rightFormat] ?? Int.max
        if left == right {
            return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
        }
        return left < right
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
