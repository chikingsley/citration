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
    let onRemoveTag: (String) -> Void
    let onDropItemIDsOnCollection: ([UUID], LibraryCollection) -> Void
    let onDropItemIDsOnTag: ([UUID], String) -> Void

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
                            collectionLabel(node.collection)
                        }
                    }
                }

                if !tags.isEmpty {
                    Section("Tags") {
                        DisclosureGroup("All Tags") {
                            ForEach(tags, id: \.self) { tag in
                                tagLabel(tag)
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

    @State private var targetedCollectionID: UUID?
    @State private var targetedTag: String?

    private var tags: [String] {
        Set(model.items.flatMap(\.tags)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func collectionLabel(_ collection: LibraryCollection) -> some View {
        Label(collection.name, systemImage: "folder")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(.rect)
            .background(
                targetedCollectionID == collection.id
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .tag(LibrarySource.collection(collection.id))
            .dropDestination(for: String.self) { payloads, _ in
                let ids = payloads.compactMap(LibraryItemDragPayload.decode).flatMap(\.self)
                guard !ids.isEmpty else {
                    return false
                }
                onDropItemIDsOnCollection(ids, collection)
                return true
            } isTargeted: { targeted in
                targetedCollectionID = targeted ? collection.id : nil
            }
            .contextMenu {
                Button("Remove Collection…", systemImage: "trash", role: .destructive) {
                    onRemoveCollection(collection)
                }
            }
    }

    private func tagLabel(_ tag: String) -> some View {
        Label(tag, systemImage: "tag")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(.rect)
            .background(
                targetedTag == tag
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .tag(LibrarySource.tag(tag))
            .dropDestination(for: String.self) { payloads, _ in
                let ids = payloads.compactMap(LibraryItemDragPayload.decode).flatMap(\.self)
                guard !ids.isEmpty else {
                    return false
                }
                onDropItemIDsOnTag(ids, tag)
                return true
            } isTargeted: { targeted in
                targetedTag = targeted ? tag : nil
            }
            .contextMenu {
                Button("Remove Tag from Library…", systemImage: "trash", role: .destructive) {
                    onRemoveTag(tag)
                }
            }
    }
}
