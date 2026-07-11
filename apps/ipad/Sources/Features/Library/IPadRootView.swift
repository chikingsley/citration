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
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") {
                            model.openDocument = nil
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                }
            }
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
            IPadItemDetailView(model: model, item: item)
        } else {
            ContentUnavailableView("Select an Item", systemImage: "doc.text.magnifyingglass")
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

// MARK: - IPadItemDetailView

private struct IPadItemDetailView: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    let item: SynchronizedLibraryItem

    var body: some View {
        List {
            Section {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                if !item.creators.isEmpty {
                    Text(item.creators.map(\.displayName).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Type", value: item.zoteroItemType)
                if !item.zoteroDate.isEmpty {
                    LabeledContent("Date", value: item.zoteroDate)
                }
                if !item.publicationTitle.isEmpty {
                    LabeledContent("Publication", value: item.publicationTitle)
                }
                if !item.projected.abstractNote.isEmpty {
                    Text(item.projected.abstractNote)
                }
                metadata("DOI", item.projected.doi)
                metadata("ISBN", item.projected.isbn)
                metadata("ISSN", item.projected.issn)
                metadata("URL", item.projected.url)
                metadata("Language", item.projected.language)
                metadata("Rights", item.projected.rights)
                metadata("Extra", item.projected.extra)
            }
            Section("Documents") {
                if model.attachmentRecords.isEmpty {
                    Text("No attachments")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.attachmentRecords) { record in
                        HStack {
                            Label(record.filename, systemImage: documentIcon(record))
                            Spacer()
                            attachmentAction(record)
                        }
                    }
                }
            }
            if !item.tags.isEmpty {
                Section("Tags") {
                    Text(item.tags.joined(separator: ", "))
                }
            }
            Section("Notes") {
                if model.selectedNotes.isEmpty {
                    Text("No notes")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.selectedNotes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            IPadNoteHTMLView(html: note.html)
                                .frame(minHeight: 88, idealHeight: 140, maxHeight: 220)
                            HStack {
                                Text(note.updatedAt, style: .date)
                                Spacer()
                                Text("v\(note.version)")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @ViewBuilder
    private func metadata(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }

    @ViewBuilder
    private func attachmentAction(_ record: ZoteroAttachmentCacheRecord) -> some View {
        switch record.cacheState {
        case .downloaded:
            if let localURL = record.localURL {
                Button("Open") {
                    model.open(item: item, record: record, url: localURL)
                }
            }

        case .downloading:
            ProgressView()

        case .notDownloaded,
             .stale,
             .failed:
            Button(record.cacheState == .failed ? "Retry" : "Download") {
                Task { await model.download(record) }
            }
            .disabled(model.isWorking)
        }
    }

    private func documentIcon(_ record: ZoteroAttachmentCacheRecord) -> String {
        switch DocumentFormat.infer(fileName: record.filename, contentType: record.contentType) {
        case .pdf: "doc.richtext"
        case .epub: "book.closed"
        case .html: "globe"
        case .plainText: "doc.plaintext"
        default: "doc"
        }
    }
}

// MARK: - IPadDocumentView

private struct IPadDocumentView: View {
    @Bindable var model: IPadLibraryModel

    let item: SynchronizedLibraryItem
    let record: ZoteroAttachmentCacheRecord
    let url: URL

    var body: some View {
        switch DocumentFormat.infer(fileName: url.lastPathComponent, contentType: record.contentType) {
        case .pdf:
            IPadPDFReaderView(model: model, item: item, record: record, url: url)

        case .plainText:
            IPadPlainTextReaderView(model: model, item: item, record: record, url: url)

        case .epub,
             .html:
            if DocumentFormat.infer(fileName: url.lastPathComponent, contentType: record.contentType) == .epub {
                IPadEPUBReaderView(model: model, item: item, record: record, url: url)
            } else {
                IPadWebDocumentView(
                    url: url,
                    format: .html,
                    progress: model.readerProgress,
                    onProgress: { offset, fraction in
                        model.updateTextProgress(
                            item: item,
                            record: record,
                            textOffset: offset,
                            fractionComplete: fraction
                        )
                    }
                )
                .navigationTitle(record.filename)
                .task(id: record.itemKey) {
                    await model.openReader(item: item, record: record)
                }
            }

        default:
            ContentUnavailableView("Unsupported Document", systemImage: "doc.questionmark")
        }
    }
}
