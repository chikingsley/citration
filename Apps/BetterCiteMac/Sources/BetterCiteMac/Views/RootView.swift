import SwiftUI
import UniformTypeIdentifiers
import Inject
import BCDomain

// MARK: - Search Scope

enum SearchScope: String, CaseIterable {
    case allFields = "All Fields & Tags"
    case title     = "Title"
    case creator   = "Creator"
    case year      = "Year"
}

// MARK: - Root

struct RootView: View {
    @ObserveInjection private var inject
    @Bindable var model: AppModel

    @State private var inspectorPresented = true
    @State private var searchText = ""
    @State private var searchScope = SearchScope.allFields
    @State private var selectedCollection: String? = "library"
    @State private var selectedItemIDs = Set<UUID>()
    @State private var libraryExpanded = true
    @State private var attachmentImporterPresented = false
    @State private var isImportDropTargeted = false
    @State private var isAttachDropTargeted = false
    @State private var importDragBorderPhase: CGFloat = 0
    @State private var attachDragBorderPhase: CGFloat = 0

    private var filteredItems: [BCItem] {
        guard !searchText.isEmpty else { return model.items }
        return model.items.filter { item in
            switch searchScope {
            case .allFields:
                return item.title.localizedCaseInsensitiveContains(searchText) ||
                    (item.creators.first?.displayName.localizedCaseInsensitiveContains(searchText) ?? false)
            case .title:
                return item.title.localizedCaseInsensitiveContains(searchText)
            case .creator:
                return item.creators.first?.displayName.localizedCaseInsensitiveContains(searchText) ?? false
            case .year:
                return item.publicationYear.map(String.init)?.contains(searchText) ?? false
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedCollection) {
                    DisclosureGroup(isExpanded: $libraryExpanded) {
                        Label { Text("My Publications") } icon: {
                            Image(systemName: "person.fill").foregroundStyle(.green)
                        }.tag("publications")
                        Label { Text("Duplicate Items") } icon: {
                            Image(systemName: "doc.on.doc.fill").foregroundStyle(.orange)
                        }.tag("duplicates")
                        Label { Text("Unfiled Items") } icon: {
                            Image(systemName: "tray.fill").foregroundStyle(Color(white: 0.5))
                        }.tag("unfiled")
                        Label { Text("Trash") } icon: {
                            Image(systemName: "trash.fill").foregroundStyle(.red)
                        }.tag("trash")
                    } label: {
                        Label { Text("My Library") } icon: {
                            Image(systemName: "building.columns.fill").foregroundStyle(.blue)
                        }.tag("library")
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("BetterCite")
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)

                importDropZone
                tagsPanel
            }
            .onDrop(
                of: [.fileURL],
                delegate: FileURLDropDelegate(
                    onTargetedChange: { targeted in
                        isImportDropTargeted = targeted
                    },
                    onDropURLs: { urls in
                        dispatchDropImport(urls: urls, mode: .createNewItemPerFile)
                    }
                )
            )
        } detail: {
            Group {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "tray",
                        description: Text("Your library is empty. Add items to get started.")
                    )
                } else {
                    Table(filteredItems, selection: $selectedItemIDs) {
                        TableColumn("Title") { item in
                            Label(item.title.bcCollapsedWhitespace(), systemImage: "doc.text")
                        }
                        TableColumn("Creator") { item in
                            Text(authorSummary(for: item))
                        }
                        .width(min: 80, ideal: 160, max: 300)
                        TableColumn("Year") { item in
                            Text(item.publicationYear.map(String.init) ?? "")
                        }
                        .width(min: 40, ideal: 60, max: 80)
                    }
                    .onChange(of: selectedItemIDs) { _, selection in
                        syncPrimarySelection(from: selection)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        .searchScopes($searchScope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .toolbar {
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

                Button("New Note", systemImage: "note.text.badge.plus") {
                    model.statusMessage = "Notes are not implemented yet"
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
        .inspector(isPresented: $inspectorPresented) {
            inspectorContent
                .inspectorColumnWidth(min: 240, ideal: 310, max: 450)
                .onDrop(
                    of: [.fileURL],
                    delegate: FileURLDropDelegate(
                        onTargetedChange: { targeted in
                            isAttachDropTargeted = targeted
                        },
                        onDropURLs: { urls in
                            dispatchDropImport(urls: urls, mode: .attachToSelectedItem)
                        }
                    )
                )
                .overlay(alignment: .top) {
                    if isAttachDropTargeted {
                        zoneBadge(
                            title: "Drop Here to Attach to Selected Item",
                            targeted: isAttachDropTargeted
                        )
                        .padding(.top, 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .overlay {
                    if isAttachDropTargeted {
                        attachDropOverlay
                            .padding(8)
                            .transition(.opacity)
                    }
                }
        }
        .fileImporter(
            isPresented: $attachmentImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importAttachments(urls: urls)
            case .failure(let error):
                model.statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        .onDeleteCommand {
            if selectedItemIDs.isEmpty {
                model.removeSelectedItem()
                return
            }
            model.removeItems(ids: Array(selectedItemIDs))
            selectedItemIDs.removeAll()
        }
        .onAppear {
            syncTableSelection(with: model.selectedItemID)
        }
        .onChange(of: model.selectedItemID) { _, id in
            syncTableSelection(with: id)
        }
        .onChange(of: isImportDropTargeted) { _, targeted in
            if targeted {
                importDragBorderPhase = 0
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    importDragBorderPhase = -42
                }
            } else {
                importDragBorderPhase = 0
            }
        }
        .onChange(of: isAttachDropTargeted) { _, targeted in
            if targeted {
                attachDragBorderPhase = 0
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    attachDragBorderPhase = -42
                }
            } else {
                attachDragBorderPhase = 0
            }
        }
        .enableInjection()
    }

    // MARK: - Tags Panel

    private var importDropZone: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: isImportDropTargeted ? "square.and.arrow.down.fill" : "square.and.arrow.down")
                Text("Drop Here to Import as New Items")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(isImportDropTargeted ? 0.22 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(isImportDropTargeted ? 0.95 : 0.35),
                        style: StrokeStyle(
                            lineWidth: isImportDropTargeted ? 2 : 1,
                            dash: [8, 5],
                            dashPhase: importDragBorderPhase
                        )
                    )
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.15), value: isImportDropTargeted)
        }
        .background(.bar)
        .overlay(alignment: .topLeading) {
            if isImportDropTargeted {
                zoneBadge(
                    title: "Drop to Import New Items",
                    targeted: isImportDropTargeted
                )
                .padding(.top, -34)
                .padding(.leading, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    private func zoneBadge(title: String, targeted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: targeted ? "checkmark.circle.fill" : "circle")
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    Color.accentColor.opacity(targeted ? 0.95 : 0.45),
                    style: StrokeStyle(lineWidth: targeted ? 1.4 : 1)
                )
        )
        .animation(.easeInOut(duration: 0.14), value: targeted)
    }

    private var attachDropOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.accentColor.opacity(0.95),
                style: StrokeStyle(lineWidth: 2.5, dash: [12, 8], dashPhase: attachDragBorderPhase)
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.14), value: isAttachDropTargeted)
    }

    private var tagsPanel: some View {
        VStack(spacing: 0) {
            Divider()
            Text("No tags to display")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 60)
            Divider()
            HStack {
                Text("Filter Tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    // MARK: - Inspector Content

    @ViewBuilder
    private var inspectorContent: some View {
        if let item = model.selectedItem {
            ScrollView {
                Form {
                    Section("Info") {
                        LabeledContent("Title") {
                            Text(item.title.bcCollapsedWhitespace()).textSelection(.enabled)
                        }
                        if let doi = item.doi {
                            LabeledContent("DOI") {
                                Text(doi).textSelection(.enabled)
                            }
                        }
                        LabeledContent("Year", value: item.publicationYear.map(String.init) ?? "n.d.")
                        LabeledContent("Creator", value: item.creators.first?.displayName ?? "Unknown")
                        if item.creators.count > 1 {
                            LabeledContent("Authors", value: item.creators.map(\.displayName).joined(separator: ", "))
                        }
                    }
                    Section("Citation Preview") {
                        Text(model.citationPreview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Section("Attachments") {
                        let isProcessingThisItem = model.reprocessingItemID == model.selectedItemID
                        let isProcessingOtherItem = model.reprocessingItemID != nil && !isProcessingThisItem

                        HStack {
                            Button(isProcessingThisItem ? "Processing..." : "Process Metadata") {
                                model.reprocessSelectedItemAttachments()
                            }
                            .disabled(
                                isProcessingThisItem
                                    || isProcessingOtherItem
                                    || model.isImportingAttachments
                                    || model.selectedItemAttachments.isEmpty
                            )
                            Spacer()
                        }

                        if model.selectedItemAttachments.isEmpty {
                            Text("No attachments yet. Use Attach or drag a PDF into this sidebar.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.selectedItemAttachments) { attachment in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(attachment.fileName)
                                        Text(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Link("Open", destination: attachment.localURL)
                                    Button {
                                        model.removeAttachment(attachment)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove attachment")
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select an item to view its details.")
            )
        }
    }

    private func authorSummary(for item: BCItem) -> String {
        let names = item.creators.map(\.displayName).filter { !$0.isEmpty }
        guard let first = names.first else {
            return ""
        }
        if names.count > 1 {
            return "\(first) et al."
        }
        return first
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

        let expected = selectedItemID.map { Set([ $0 ]) } ?? []
        if expected != selectedItemIDs {
            selectedItemIDs = expected
        }
    }

    private func dispatchDropImport(urls: [URL], mode: AppModel.AttachmentImportMode) {
        DispatchQueue.main.async {
            model.importAttachments(urls: urls, mode: mode)
        }
    }
}

private struct FileURLDropDelegate: DropDelegate {
    let onTargetedChange: (Bool) -> Void
    let onDropURLs: ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        onTargetedChange(true)
    }

    func dropExited(info: DropInfo) {
        onTargetedChange(false)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetedChange(false)

        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            return false
        }

        Self.loadFileURLs(from: providers) { urls in
            onDropURLs(urls)
        }
        return true
    }

    private nonisolated static func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let collector = URLCollector()

        for provider in providers {
            group.enter()
            loadSingleFileURL(from: provider) { url in
                defer { group.leave() }
                guard let url, url.isFileURL else {
                    return
                }
                collector.append(url)
            }
        }

        group.notify(queue: .main) {
            completion(Self.dedupeFileURLs(collector.snapshot()))
        }
    }

    private nonisolated static func loadSingleFileURL(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) {
        if provider.canLoadObject(ofClass: NSURL.self) {
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let nsURL = object as? NSURL {
                    completion(nsURL as URL)
                } else {
                    completion(nil)
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                completion(Self.parseFileURL(from: item))
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _, _ in
                completion(url)
            }
            return
        }

        completion(nil)
    }

    private nonisolated static func parseFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let nsURL = item as? NSURL {
            return nsURL as URL
        }
        if let urls = item as? [URL] {
            return urls.first
        }
        if let nsURLs = item as? [NSURL] {
            return nsURLs.first as URL?
        }
        if let string = item as? String {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let string = item as? NSString {
            return URL(string: String(string).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let data = item as? Data,
           let fileURL = URL(dataRepresentation: data, relativeTo: nil),
           fileURL.isFileURL {
            return fileURL
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private nonisolated static func dedupeFileURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var output = [URL]()

        for url in urls {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                output.append(standardized)
            }
        }
        return output
    }

    private final class URLCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var urls = [URL]()

        func append(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        func snapshot() -> [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }
    }
}
