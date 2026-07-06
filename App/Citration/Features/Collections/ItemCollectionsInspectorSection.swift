import CitrationCore
import SwiftUI

struct ItemCollectionsInspectorSection: View {
    // MARK: Internal

    @Bindable var model: AppModel

    let item: BCItem

    var body: some View {
        Section("Collections") {
            if model.collections.isEmpty {
                Text("No collections")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.collections) { collection in
                    Toggle(isOn: membershipBinding(for: collection)) {
                        Label(collection.name, systemImage: "folder")
                    }
                }
            }

            Button("New Collection", systemImage: "folder.badge.plus") {
                model.createCollection()
            }
        }
    }

    // MARK: Private

    private func membershipBinding(for collection: LibraryCollection) -> Binding<Bool> {
        Binding {
            model.selectedItemCollectionIDs.contains(collection.id)
        } set: { isMember in
            model.setSelectedItem(item, memberOf: collection, isMember: isMember)
        }
    }
}
