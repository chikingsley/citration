import CitrationCore
import SwiftUI

// MARK: - IPadRootView

struct IPadRootView: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            libraryList
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $model.searchText, prompt: "Search library")
        .onChange(of: model.searchText) {
            model.updateSearch()
        }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
        .sheet(isPresented: $model.settingsPresented) {
            IPadConnectionSettingsView(model: model)
        }
        .fullScreenCover(item: $model.openDocument) { document in
            NavigationStack {
                IPadDocumentView(
                    model: model,
                    item: document.item,
                    record: document.record,
                    url: document.url
                )
            }
        }
        .confirmationDialog(
            "Choose a Document",
            isPresented: documentChoicesPresented,
            titleVisibility: .visible
        ) {
            ForEach(model.pendingDocumentChoices) { record in
                Button(record.filename) {
                    model.openDocumentChoice(record)
                }
            }
            Button("Cancel", role: .cancel) {
                model.dismissDocumentChoices()
            }
        } message: {
            Text("This item has more than one readable attachment.")
        }
        .task {
            await model.start()
            await model.restoreScene(
                sourceToken: restoredSourceToken,
                itemKey: restoredItemKey,
                attachmentKey: restoredAttachmentKey
            )
        }
        .onChange(of: model.selectedSource) { _, source in
            restoredSourceToken = model.sceneToken(for: source)
        }
        .onChange(of: model.selectedItemIdentity) { _, identity in
            restoredItemKey = identity?.objectKey ?? ""
        }
        .onChange(of: model.openDocument?.id) { _, attachmentKey in
            restoredAttachmentKey = attachmentKey ?? ""
        }
    }

    // MARK: Private

    @SceneStorage("citration.source") private var restoredSourceToken = "all"
    @SceneStorage("citration.item") private var restoredItemKey = ""
    @SceneStorage("citration.attachment") private var restoredAttachmentKey = ""

    private var documentChoicesPresented: Binding<Bool> {
        Binding(
            get: { !model.pendingDocumentChoices.isEmpty },
            set: { presented in
                if !presented {
                    model.dismissDocumentChoices()
                }
            }
        )
    }

    private var sidebar: some View {
        List(selection: $model.selectedSource) {
            Section("Library") {
                Label("All Items", systemImage: "tray.full")
                    .tag(IPadLibraryModel.Source.allItems)
            }
            if !model.collections.collections.isEmpty {
                Section("Collections") {
                    ForEach(model.collections.collections) { collection in
                        Label(collection.name, systemImage: "folder")
                            .tag(IPadLibraryModel.Source.collection(collection.id))
                    }
                }
            }
            if !model.availableTags.isEmpty {
                Section("Tags") {
                    ForEach(model.availableTags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(IPadLibraryModel.Source.tag(tag))
                    }
                }
            }
        }
        .navigationTitle("Citration")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gear") {
                    model.settingsPresented = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private var libraryList: some View {
        Group {
            if model.visibleItems.isEmpty {
                ContentUnavailableView(
                    model.searchText.isEmpty ? "No Items" : "No Results",
                    systemImage: model.searchText.isEmpty ? "tray" : "magnifyingglass"
                )
            } else {
                List(model.visibleItems, selection: Binding(
                    get: { model.selectedItemIdentity },
                    set: { model.selectItem($0) }
                )) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                Text(item.creators.first?.displayName ?? item.zoteroItemType)
                                if let year = item.publicationYear {
                                    Text(String(year))
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if model.openingItemIdentity == item.identity {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .tag(item.identity)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sync", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.synchronize() }
                }
                .disabled(model.isWorking || model.configuration == .localOnly)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let item = model.selectedItem {
            IPadItemLandingView(model: model, item: item)
        } else {
            ContentUnavailableView("Choose Something to Read", systemImage: "books.vertical")
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.statusMessage)
                .lineLimit(1)
            Spacer()
            if let syncStatus = model.syncStatus {
                IPadSyncStatusMenu(model: model, status: syncStatus)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - IPadSyncStatusMenu

private struct IPadSyncStatusMenu: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    let status: ZoteroSyncStatusSnapshot

    var body: some View {
        Menu {
            Text("Library version \(status.currentVersion)")
            if status.pendingChangeCount > 0 {
                Label("\(status.pendingChangeCount) pending changes", systemImage: "arrow.up.arrow.down")
            }
            if status.failedAttachmentCount > 0 {
                Label("\(status.failedAttachmentCount) failed attachments", systemImage: "exclamationmark.icloud")
            }
            ForEach(status.failures) { failure in
                failureMenu(failure)
            }
            if !status.failures.isEmpty {
                Divider()
                Button("Retry All Failures", systemImage: "arrow.clockwise") {
                    Task { await model.retryAllSyncFailures() }
                }
                .disabled(!model.recoveringFailureIDs.isEmpty)
            }
        } label: {
            if !status.failures.isEmpty {
                Label("\(status.failures.count) failures", systemImage: "exclamationmark.triangle.fill")
            } else if status.pendingChangeCount > 0 {
                Label("\(status.pendingChangeCount) pending", systemImage: "arrow.up.arrow.down")
            } else {
                Label("v\(status.currentVersion)", systemImage: "checkmark.icloud")
            }
        }
        .monospacedDigit()
    }

    // MARK: Private

    private func failureMenu(_ failure: ZoteroSyncFailureSummary) -> some View {
        Menu {
            Text(failure.message)
            Text("\(failure.objectKind.rawValue):\(failure.objectKey)")
                .font(.caption.monospaced())
            Button("Retry Now", systemImage: "arrow.clockwise") {
                Task { await model.retrySyncFailure(failure) }
            }
            if failure.operation == "merge-conflict" {
                Divider()
                Button("Keep Local Version") {
                    Task { await model.resolveSyncConflict(failure, resolution: .keepLocal) }
                }
                Button("Keep Remote Version") {
                    Task { await model.resolveSyncConflict(failure, resolution: .keepRemote) }
                }
                Button("Delete Object", role: .destructive) {
                    Task { await model.resolveSyncConflict(failure, resolution: .delete) }
                }
            }
        } label: {
            Label(failure.operation, systemImage: "exclamationmark.triangle")
        }
        .disabled(model.recoveringFailureIDs.contains(failure.id))
    }
}
