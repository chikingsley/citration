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
                selectedCollection: $selectedCollection,
                selectedTag: $selectedTag,
                libraryExpanded: $libraryExpanded,
                isImportDropTargeted: $isImportDropTargeted,
                importDragBorderPhase: importDragBorderPhase,
                onDropURLs: { urls in
                    dispatchDropImport(urls: urls, mode: .createNewItemPerFile)
                },
                onRemoveCollection: removeCollection
            )
            .onAppear {
                model.selectCollection(id: LibrarySelectionIdentifier.collectionID(from: selectedCollection))
            }
            .onChange(of: selectedCollection) { _, selection in
                selectedTag = nil
                model.selectCollection(id: LibrarySelectionIdentifier.collectionID(from: selection))
            }
            .onChange(of: model.selectedCollectionID) { _, collectionID in
                selectedCollection = LibrarySelectionIdentifier.value(for: collectionID)
            }
        } detail: {
            LibraryDetailView(
                model: model,
                filteredItems: filteredItems,
                selectedItemIDs: $selectedItemIDs,
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
        .onDeleteCommand {
            deleteSelection()
        }
        .onAppear {
            syncTableSelection(with: model.selectedItemID)
        }
        .onChange(of: model.selectedItemID) { _, id in
            syncTableSelection(with: id)
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
    @State private var selectedTag: String?
    @State private var selectedCollection: String? = LibrarySelectionIdentifier.library
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var libraryExpanded = true
    @State private var attachmentImporterPresented = false
    @State private var isImportDropTargeted = false
    @State private var isAttachDropTargeted = false
    @State private var importDragBorderPhase: CGFloat = 0
    @State private var attachDragBorderPhase: CGFloat = 0

    @ObserveInjection private var inject

    private var filteredItems: [BCItem] {
        let collectionItems = model.selectedCollectionItems
        let scopedItems: [BCItem] = if let selectedTag {
            collectionItems.filter { item in
                item.tags.contains { $0.localizedCaseInsensitiveCompare(selectedTag) == .orderedSame }
            }
        } else {
            collectionItems
        }

        guard !searchText.isEmpty else {
            return scopedItems
        }
        return scopedItems.filter { item in
            switch searchScope {
            case .allFields:
                item.title.localizedCaseInsensitiveContains(searchText)
                    || (item.creators.first?.displayName.localizedCaseInsensitiveContains(searchText) ?? false)
                    || item.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }

            case .title:
                item.title.localizedCaseInsensitiveContains(searchText)

            case .creator:
                item.creators.first?.displayName.localizedCaseInsensitiveContains(searchText) ?? false

            case .year:
                item.publicationYear.map(String.init)?.contains(searchText) ?? false

            case .tags:
                item.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    @ToolbarContentBuilder
    private var rootToolbar: some ToolbarContent {
        ToolbarItemGroup {
            TextField("DOI", text: $model.doiInput)
                .frame(width: 260)
            Button(model.isResolvingDOI ? "Resolving..." : "Add DOI", systemImage: "plus.circle") {
                model.addByDOI()
            }
            .disabled(model.isResolvingDOI)

            Button("New Item", systemImage: "doc.badge.plus") {
                model.addEmptyItem()
            }

            Button("New Collection", systemImage: "folder.badge.plus") {
                model.createCollection()
            }

            Button("New Note", systemImage: "note.text.badge.plus") {
                model.prepareNewItemNote()
            }

            Button("Attach", systemImage: "paperclip") {
                attachmentImporterPresented = true
            }
        }
        ToolbarItem(placement: .status) {
            Text(model.statusMessage)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                inspectorPresented.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
        }
    }

    private func handleImportedAttachments(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            model.importAttachments(urls: urls)
        case let .failure(error):
            model.statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func deleteSelection() {
        if selectedItemIDs.isEmpty {
            model.removeSelectedItem()
            return
        }
        model.removeItems(ids: Array(selectedItemIDs))
        selectedItemIDs.removeAll()
    }

    private func syncPrimarySelection(from selection: Set<UUID>) {
        guard !selection.isEmpty else {
            model.selectItem(id: nil)
            return
        }

        if selection.count == 1 {
            model.selectItem(id: selection.first)
            return
        }

        if let current = model.selectedItemID, selection.contains(current) {
            return
        }

        if let visible = filteredItems.first(where: { selection.contains($0.id) })?.id {
            model.selectItem(id: visible)
            return
        }

        model.selectItem(id: selection.first)
    }

    private func syncTableSelection(with selectedItemID: UUID?) {
        guard selectedItemIDs.count <= 1 else {
            return
        }

        let expected = selectedItemID.map { Set([$0]) } ?? []
        if expected != selectedItemIDs {
            selectedItemIDs = expected
        }
    }

    private func dispatchDropImport(urls: [URL], mode: AppModel.AttachmentImportMode) {
        DispatchQueue.main.async {
            model.importAttachments(urls: urls, mode: mode)
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
        if selectedCollection == LibrarySelectionIdentifier.value(for: collection) {
            selectedCollection = LibrarySelectionIdentifier.library
        }
        model.removeCollection(collection)
    }
}
