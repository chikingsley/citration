import CitrationCore
import SwiftUI

// MARK: - IPadRootView

struct IPadRootView: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            library
        }
        .navigationSplitViewStyle(.prominentDetail)
        .inspector(isPresented: $model.inspectorPresented) {
            inspector
                .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
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
        .modifier(IPadForegroundSyncLifecycle(model: model))
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
    @State private var collectionsExpanded = true
    @State private var tagsExpanded = false

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

    private var openActionTitle: String {
        let readable = readableAttachments
        guard readable.count == 1, let record = readable.first else {
            return readable.isEmpty ? "Open" : "Choose"
        }
        return record.cacheState == .downloaded ? "Open" : "Download"
    }

    private var openActionIcon: String {
        switch openActionTitle {
        case "Download": "arrow.down.circle"
        case "Choose": "doc.on.doc"
        default: "book.pages"
        }
    }

    private var readableAttachments: [ZoteroAttachmentCacheRecord] {
        model.attachmentRecords.filter {
            DocumentFormat.infer(fileName: $0.filename, contentType: $0.contentType).isSupportedOnIPad
        }
    }

    private var accountStatusText: String {
        if model.isWorking {
            return model.statusMessage
        }
        switch model.configuration {
        case .localOnly:
            return "Local only"
        case .connected:
            return model.syncStatus?.pendingChangeCount == 0 ? "Up to date" : model.statusMessage
        }
    }

    private var sidebar: some View {
        List(selection: $model.selectedSource) {
            Label("All Items", systemImage: "tray.full")
                .tag(IPadLibraryModel.Source.allItems)

            if !model.collections.collections.isEmpty {
                DisclosureGroup(isExpanded: $collectionsExpanded) {
                    ForEach(model.collections.collections) { collection in
                        Label(collection.name, systemImage: "folder")
                            .tag(IPadLibraryModel.Source.collection(collection.id))
                    }
                } label: {
                    Label("Collections", systemImage: "folder.fill")
                }
            }

            if !model.availableTags.isEmpty {
                DisclosureGroup(isExpanded: $tagsExpanded) {
                    ForEach(model.availableTags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(IPadLibraryModel.Source.tag(tag))
                    }
                } label: {
                    Label("Tags", systemImage: "tag.fill")
                }
            }
        }
        .navigationTitle("Citration")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            accountMenu
        }
    }

    private var accountMenu: some View {
        Menu {
            Text(model.accountDisplayName)
            connectionStatus
            Divider()
            Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                Task { await model.synchronize() }
            }
            .disabled(model.isWorking || model.configuration == .localOnly)
            Button("Settings", systemImage: "gearshape") {
                model.settingsPresented = true
            }
            .keyboardShortcut(",", modifiers: .command)
        } label: {
            HStack(spacing: 10) {
                Text(model.accountInitials)
                    .font(.caption.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(.tint, in: Circle())
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.accountDisplayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(accountStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account and settings for \(model.accountDisplayName)")
    }

    private var library: some View {
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
                    itemRow(item)
                        .tag(item.identity)
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            if model.selectedItemIdentity != item.identity {
                                model.selectItem(item.identity)
                            }
                            model.openSelectedItem()
                        })
                }
            }
        }
        .navigationTitle(model.selectedSourceTitle)
        .searchable(text: $model.searchText, prompt: "Search \(model.selectedSourceTitle)")
        .onChange(of: model.searchText) {
            model.updateSearch()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Open", systemImage: "book.pages") {
                    model.openSelectedItem()
                }
                .disabled(model.selectedItem == nil || model.selectionLoadingIdentity != nil)
                .keyboardShortcut(.return, modifiers: [])

                Button("Info", systemImage: "info.circle") {
                    model.inspectorPresented.toggle()
                }
                .disabled(model.selectedItem == nil)

                if let status = model.syncStatus {
                    IPadSyncStatusMenu(model: model, status: status)
                }
            }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let item = model.selectedItem {
            IPadItemInfoView(model: model, item: item)
        } else {
            ContentUnavailableView("No Selection", systemImage: "info.circle")
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch model.configuration {
        case .localOnly:
            Label("Local Only", systemImage: "externaldrive")
        case let .connected(profile):
            Label(profile.serverURL.host() ?? "Connected", systemImage: "checkmark.icloud")
        }
    }

    private func itemRow(_ item: SynchronizedLibraryItem) -> some View {
        HStack(spacing: 12) {
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
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.selectedItemIdentity == item.identity {
                selectedItemAccessory(item)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Open", systemImage: "book.pages") {
                if model.selectedItemIdentity != item.identity {
                    model.selectItem(item.identity)
                }
                model.openSelectedItem()
            }
            Button("Show Info", systemImage: "info.circle") {
                model.selectItem(item.identity)
                model.inspectorPresented = true
            }
        }
    }

    @ViewBuilder
    private func selectedItemAccessory(_ item: SynchronizedLibraryItem) -> some View {
        if model.selectionLoadingIdentity == item.identity {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading document information")
        } else if model.openingItemIdentity == item.identity {
            let progress = model.attachmentDownloadProgress.values.first
            VStack(alignment: .trailing, spacing: 4) {
                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 92)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        } else if !model.attachmentRecords.isEmpty {
            Button(openActionTitle, systemImage: openActionIcon) {
                model.openSelectedItem()
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - IPadForegroundSyncLifecycle

private struct IPadForegroundSyncLifecycle: ViewModifier {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            Task {
                if phase == .active {
                    await model.startAutomaticSynchronization()
                } else if phase == .background {
                    await model.stopAutomaticSynchronization()
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.scenePhase) private var scenePhase
}

// MARK: - IPadSyncStatusMenu

private struct IPadSyncStatusMenu: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    let status: ZoteroSyncStatusSnapshot

    var body: some View {
        Menu {
            if status.pendingChangeCount > 0 {
                Label("\(status.pendingChangeCount) pending changes", systemImage: "arrow.up.arrow.down")
            } else {
                Label("Up to Date", systemImage: "checkmark.icloud")
            }
            if status.failedAttachmentCount > 0 {
                Label("\(status.failedAttachmentCount) failed attachments", systemImage: "exclamationmark.icloud")
            }
            ForEach(status.failures) { failure in
                failureMenu(failure)
            }
            Divider()
            Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                Task { await model.synchronize() }
            }
            .disabled(model.isWorking || model.configuration == .localOnly)
            if !status.failures.isEmpty {
                Button("Retry All Failures", systemImage: "arrow.clockwise") {
                    Task { await model.retryAllSyncFailures() }
                }
                .disabled(!model.recoveringFailureIDs.isEmpty)
            }
        } label: {
            if model.isWorking {
                Label(model.statusMessage, systemImage: "arrow.triangle.2.circlepath")
            } else if !status.failures.isEmpty {
                Label("\(status.failures.count) Failures", systemImage: "exclamationmark.triangle.fill")
            } else if status.pendingChangeCount > 0 {
                Label("\(status.pendingChangeCount) Pending", systemImage: "arrow.up.arrow.down")
            } else {
                Label("Up to Date", systemImage: "checkmark.icloud")
            }
        }
    }

    // MARK: Private

    private func failureMenu(_ failure: ZoteroSyncFailureSummary) -> some View {
        Menu("\(failure.operation): \(failure.objectKey)") {
            if failure.operation == "merge-conflict" {
                Button("Keep Local") {
                    Task { await model.resolveSyncConflict(failure, resolution: .keepLocal) }
                }
                Button("Keep Remote") {
                    Task { await model.resolveSyncConflict(failure, resolution: .keepRemote) }
                }
                Button("Delete") {
                    Task { await model.resolveSyncConflict(failure, resolution: .delete) }
                }
            } else {
                Button("Retry") {
                    Task { await model.retrySyncFailure(failure) }
                }
            }
        }
        .disabled(model.recoveringFailureIDs.contains(failure.id))
    }
}
