import CitrationCore
import SwiftUI

struct ItemCollectionsInspectorSection: View {
    // MARK: Internal

    @Bindable var model: AppModel

    let item: BCItem

    var body: some View {
        Section("Collections") {
            if model.collections.all.isEmpty {
                Text("No collections")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.collections.all) { collection in
                    Toggle(isOn: membershipBinding(for: collection)) {
                        Label(collection.name, systemImage: "folder")
                    }
                }
            }

            Button("New Collection", systemImage: "folder.badge.plus") {
                model.collections.create()
            }
        }
    }

    // MARK: Private

    private func membershipBinding(for collection: LibraryCollection) -> Binding<Bool> {
        Binding {
            model.collections.selectedItemCollectionIDs.contains(collection.id)
        } set: { isMember in
            model.collections.set(item, memberOf: collection, isMember: isMember)
        }
    }
}
