import CitrationCore
import SwiftUI
import UniformTypeIdentifiers

struct RootLibrarySidebar: View {
    @Bindable var model: AppModel
    @Binding var selectedCollection: String?
    @Binding var selectedTag: String?
    @Binding var libraryExpanded: Bool
    @Binding var isImportDropTargeted: Bool

    let importDragBorderPhase: CGFloat
    let onDropURLs: ([URL]) -> Void
    let onRemoveCollection: (LibraryCollection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCollection) {
                DisclosureGroup(isExpanded: $libraryExpanded) {
                    Label { Text("All Items") } icon: {
                        Image(systemName: "tray.full.fill").foregroundStyle(.blue)
                    }
                    .tag(LibrarySelectionIdentifier.library)

                    if model.collections.isEmpty {
                        Text("No collections")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.collections) { collection in
                            Label(collection.name, systemImage: "folder.fill")
                                .tag(LibrarySelectionIdentifier.value(for: collection))
                                .contextMenu {
                                    Button("Remove Collection", systemImage: "trash") {
                                        onRemoveCollection(collection)
                                    }
                                }
                        }
                    }
                } label: {
                    Label { Text("My Library") } icon: {
                        Image(systemName: "building.columns.fill").foregroundStyle(.blue)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Citration")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)

            RootImportDropZone(
                targeted: isImportDropTargeted,
                dragBorderPhase: importDragBorderPhase
            )
            TagFilterPanel(items: model.selectedCollectionItems, selectedTag: $selectedTag)
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
}
