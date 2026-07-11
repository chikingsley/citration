import CitrationCore
import Inject
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SearchScope

enum SearchScope: String, CaseIterable {
    case allFields = "All Fields & Tags"
    case title = "Title"
    case creator = "Creator"
    case year = "Year"
    case tags = "Tags"
}

// MARK: - RootView

struct RootView: View {
    // MARK: Internal

    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            RootLibrarySidebar(
                model: model,
                selectedSource: $selectedSource,
                isImportDropTargeted: $isImportDropTargeted,
                importDragBorderPhase: importDragBorderPhase,
                onDropURLs: { urls in
                    dispatchDropImport(urls: urls, mode: .createNewItemPerFile)
                },
                onRemoveCollection: removeCollection
            )
            .onAppear {
                selectLibrarySource(selectedSource)
            }
            .onChange(of: selectedSource) { _, source in
                selectLibrarySource(source)
            }
            .onChange(of: model.collections.selectedID) { _, collectionID in
                if let collectionID {
                    selectedSource = .collection(collectionID)
                } else if case .some(.collection) = selectedSource {
                    selectedSource = .allItems
                }
            }
        } detail: {
            WorkspaceContentView(
                model: model,
                filteredItems: filteredItems,
                emptyState: emptyState,
                selectedItemIdentities: $selectedItemIdentities,
                onSelectionChange: syncPrimarySelection(from:)
            )
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        .searchScopes($searchScope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .toolbar {
            rootToolbar
        }
        .inspector(isPresented: $inspectorPresented) {
            RootInspectorView(
                model: model,
                isAttachDropTargeted: isAttachDropTargeted,
                attachDragBorderPhase: attachDragBorderPhase,
                onTargetedChange: { targeted in
                    isAttachDropTargeted = targeted
                },
                onDropURLs: { urls in
                    dispatchDropImport(urls: urls, mode: .attachToSelectedItem)
                }
            )
        }
        .fileImporter(
            isPresented: $attachmentImporterPresented,
            allowedContentTypes: [.pdf, .citrationEPUB],
            allowsMultipleSelection: true
        ) { result in
            handleImportedAttachments(result)
        }
        .sheet(isPresented: $addItemPresented) {
            AddItemView(
                model: model,
                onImportDocuments: {
                    addItemPresented = false
                    attachmentImporterPresented = true
                }
            )
        }
        .onDeleteCommand {
            deleteSelection()
        }
        .onAppear {
            syncTableSelection(with: model.selectedItemIdentity)
        }
        .onChange(of: model.selectedItemIdentity) { _, identity in
            syncTableSelection(with: identity)
        }
        .onChange(of: isImportDropTargeted) { _, targeted in
            updateImportDropAnimation(targeted: targeted)
        }
        .onChange(of: isAttachDropTargeted) { _, targeted in
            updateAttachDropAnimation(targeted: targeted)
        }
        .enableInjection()
    }

    // MARK: Private

    @State private var inspectorPresented = true
    @State private var searchText = ""
    @State private var searchScope: SearchScope = .allFields
    @State private var selectedSource: LibrarySource? = .allItems
    @State private var selectedItemIdentities: Set<SynchronizedLibraryItemIdentity> = []
    @State private var addItemPresented = false
    @State private var attachmentImporterPresented = false
    @State private var isImportDropTargeted = false
    @State private var isAttachDropTargeted = false
    @State private var importDragBorderPhase: CGFloat = 0
    @State private var attachDragBorderPhase: CGFloat = 0

    @ObserveInjection private var inject

    private var filteredItems: [SynchronizedLibraryItem] {
        let scopedItems: [SynchronizedLibraryItem] = switch selectedSource ?? .allItems {
        case .allItems:
            model.items

        case let .collection(collectionID):
            model.collections.items(in: collectionID)

        case let .tag(tag):
            model.items.filter { item in
                item.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }

        case .savedSearch,
             .trash:
            []
        }

        guard !searchText.isEmpty else {
            return scopedItems
        }
        return scopedItems.filter { item in
            let bibliographic = item.bibliographic
            return switch searchScope {
            case .allFields:
                bibliographic.title.localizedCaseInsensitiveContains(searchText)
                    || (bibliographic.creators.first?.displayName.localizedCaseInsensitiveContains(searchText) ?? false)
                    || bibliographic.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }

            case .title:
                bibliographic.title.localizedCaseInsensitiveContains(searchText)

            case .creator:
                bibliographic.creators.first?.displayName.localizedCaseInsensitiveContains(searchText) ?? false

            case .year:
                bibliographic.publicationYear.map(String.init)?.contains(searchText) ?? false

            case .tags:
                bibliographic.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    private var emptyState: LibraryEmptyState {
        switch selectedSource ?? .allItems {
        case .allItems:
            LibraryEmptyState(
                title: "No Items",
                systemImage: "tray",
                description: "Your library is empty. Add items to get started."
            )

        case let .collection(collectionID):
            LibraryEmptyState(
                title: "No Items",
                systemImage: "folder",
                description: model.collections.all.first(where: { $0.id == collectionID })
                    .map { "\($0.name) does not contain any items." }
                    ?? "This collection does not contain any items."
            )

        case let .tag(tag):
            LibraryEmptyState(
                title: "No Tagged Items",
                systemImage: "tag",
                description: "No items are tagged \(tag)."
            )

        case let .savedSearch(key):
            LibraryEmptyState(
                title: model.savedSearches.first(where: { $0.key == key })?.name ?? "Saved Search",
                systemImage: "magnifyingglass",
                description: "Saved-search condition evaluation is not available in this slice yet."
            )

        case .trash:
            LibraryEmptyState(
                title: model.deletedItemCount == 0 ? "Trash Is Empty" : "\(model.deletedItemCount) Deleted Items",
                systemImage: "trash",
                description: "Deleted object keys remain preserved for synchronization. Restore is not available yet."
            )
        }
    }

    @ToolbarContentBuilder
    private var rootToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Add", systemImage: "plus") {
                addItemPresented = true
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        ToolbarItem(placement: .status) {
            SyncStatusMenu(model: model)
        }
        ToolbarItem {
            Button {
                inspectorPresented.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .accessibilityLabel(inspectorPresented ? "Hide Inspector" : "Show Inspector")
            .help(inspectorPresented ? "Hide Inspector" : "Show Inspector")
        }
    }

    private func handleImportedAttachments(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            model.importer.importAttachments(urls: urls)
        case let .failure(error):
            model.statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func deleteSelection() {
        if selectedItemIdentities.isEmpty {
            model.removeSelectedItem()
            return
        }
        model.removeItems(ids: selectedItemIdentities.map(\.appUUID))
        selectedItemIdentities.removeAll()
    }

    private func syncPrimarySelection(from selection: Set<SynchronizedLibraryItemIdentity>) {
        guard !selection.isEmpty else {
            model.selectItem(identity: nil)
            return
        }

        if selection.count == 1 {
            model.selectItem(identity: selection.first)
            return
        }

        if let current = model.selectedItemIdentity, selection.contains(current) {
            return
        }

        if let visible = filteredItems.first(where: { selection.contains($0.id) })?.id {
            model.selectItem(identity: visible)
            return
        }

        model.selectItem(identity: selection.first)
    }

    private func syncTableSelection(with identity: SynchronizedLibraryItemIdentity?) {
        guard selectedItemIdentities.count <= 1 else {
            return
        }

        let expected = identity.map { Set([$0]) } ?? []
        if expected != selectedItemIdentities {
            selectedItemIdentities = expected
        }
    }

    private func dispatchDropImport(urls: [URL], mode: AttachmentImportMode) {
        DispatchQueue.main.async {
            model.importer.importAttachments(urls: urls, mode: mode)
        }
    }

    private func updateImportDropAnimation(targeted: Bool) {
        if targeted {
            importDragBorderPhase = 0
            withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                importDragBorderPhase = -42
            }
        } else {
            importDragBorderPhase = 0
        }
    }

    private func updateAttachDropAnimation(targeted: Bool) {
        if targeted {
            attachDragBorderPhase = 0
            withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                attachDragBorderPhase = -42
            }
        } else {
            attachDragBorderPhase = 0
        }
    }

    private func removeCollection(_ collection: LibraryCollection) {
        if selectedSource == .collection(collection.id) {
            selectedSource = .allItems
        }
        model.collections.remove(collection)
    }

    private func selectLibrarySource(_ source: LibrarySource?) {
        if case let .some(.collection(collectionID)) = source {
            model.collections.select(id: collectionID)
        } else {
            model.collections.select(id: nil)
        }
    }
}
