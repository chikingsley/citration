import CitrationCore
import SwiftUI

struct ItemTagsInspectorSection: View {
    @Bindable var tags: TagsModel

    let item: BCItem

    var body: some View {
        Section("Tags") {
            HStack {
                TextField("Add tag", text: $tags.draft)
                    .onSubmit {
                        tags.addToSelectedItem()
                    }
                Button {
                    tags.addToSelectedItem()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(tags.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add tag")
            }

            if item.tags.isEmpty {
                Text("No tags")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(item.tags, id: \.self) { tag in
                    HStack {
                        Label(tag, systemImage: "tag")
                        Spacer()
                        Button {
                            tags.remove(tag, from: item)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove tag")
                    }
                }
            }
        }
    }
}
