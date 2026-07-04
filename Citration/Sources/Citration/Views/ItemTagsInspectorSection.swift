import SwiftUI
import CitrationCore

struct ItemTagsInspectorSection: View {
    @Bindable var model: AppModel
    let item: BCItem

    var body: some View {
        Section("Tags") {
            HStack {
                TextField("Add tag", text: $model.tagDraft)
                    .onSubmit {
                        model.addTagToSelectedItem()
                    }
                Button {
                    model.addTagToSelectedItem()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(model.tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                            model.removeTag(tag, from: item)
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
