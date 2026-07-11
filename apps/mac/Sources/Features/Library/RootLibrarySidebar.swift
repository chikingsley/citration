import CitrationCore
import SwiftUI
import UniformTypeIdentifiers

struct RootLibrarySidebar: View {
    // MARK: Internal

    @Bindable var model: AppModel
    @Binding var selectedSource: LibrarySource?
    @Binding var isImportDropTargeted: Bool

    let importDragBorderPhase: CGFloat
    let onDropURLs: ([URL]) -> Void
    let onRemoveCollection: (LibraryCollection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSource) {
                Section("Library") {
                    Label("All Items", systemImage: "tray.full")
                        .tag(LibrarySource.allItems)
                    HStack {
                        Label("Trash", systemImage: "trash")
                        Spacer()
                        if model.deletedItemCount > 0 {
                            Text(model.deletedItemCount, format: .number)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .tag(LibrarySource.trash)
                }

                if !model.savedSearches.isEmpty {
                    Section("Saved Searches") {
                        ForEach(model.savedSearches, id: \.key) { search in
                            Label(search.name, systemImage: "magnifyingglass")
                                .tag(LibrarySource.savedSearch(search.key))
                        }
                    }
                }

                Section("Collections") {
                    if model.collections.all.isEmpty {
                        Text("No collections")
                            .foregroundStyle(.secondary)
                    } else {
                        OutlineGroup(model.collections.all.collectionTree(), children: \.children) { node in
                            Label(node.collection.name, systemImage: "folder")
                                .tag(LibrarySource.collection(node.collection.id))
                                .contextMenu {
                                    Button("Remove Collection", systemImage: "trash") {
                                        onRemoveCollection(node.collection)
                                    }
                                }
                        }
                    }
                }

                if !tags.isEmpty {
                    Section("Tags") {
                        DisclosureGroup("All Tags") {
                            ForEach(tags, id: \.self) { tag in
                                Label(tag, systemImage: "tag")
                                    .tag(LibrarySource.tag(tag))
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Citration")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)

            RootImportDropZone(
                targeted: isImportDropTargeted,
                dragBorderPhase: importDragBorderPhase
            )
        }
        .onDrop(
            of: [.fileURL],
            delegate: FileURLDropDelegate(
                onTargetedChange: { targeted in
                    isImportDropTargeted = targeted
                },
                onDropURLs: onDropURLs
            )
        )
    }

    // MARK: Private

    private var tags: [String] {
        Set(model.items.flatMap(\.tags)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
