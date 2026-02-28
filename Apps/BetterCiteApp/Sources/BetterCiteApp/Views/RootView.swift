import SwiftUI
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
    @State private var libraryExpanded = true

    var filteredItems: [BCItem] {
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                tagsPanel
            }
        } detail: {
            Group {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "tray",
                        description: Text("Your library is empty. Add items to get started.")
                    )
                } else {
                    Table(filteredItems, selection: Binding(
                        get: { model.selectedItemID },
                        set: { model.selectItem(id: $0) }
                    )) {
                        TableColumn("Title") { item in
                            Label(item.title, systemImage: "doc.text")
                        }
                        TableColumn("Creator") { item in
                            Text(item.creators.first?.displayName ?? "")
                        }
                        .width(min: 80, ideal: 160, max: 300)
                        TableColumn("Year") { item in
                            Text(item.publicationYear.map(String.init) ?? "")
                        }
                        .width(min: 40, ideal: 60, max: 80)
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
                    model.statusMessage = "Attachments are not implemented yet"
                }
                .disabled(model.selectedItem == nil)
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
        }
        .enableInjection()
    }

    // MARK: - Tags Panel

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
                            Text(item.title).textSelection(.enabled)
                        }
                        if let doi = item.doi {
                            LabeledContent("DOI") {
                                Text(doi).textSelection(.enabled)
                            }
                        }
                        LabeledContent("Year", value: item.publicationYear.map(String.init) ?? "n.d.")
                        LabeledContent("Creator", value: item.creators.first?.displayName ?? "Unknown")
                    }
                    Section("Citation Preview") {
                        Text(model.citationPreview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
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
}
