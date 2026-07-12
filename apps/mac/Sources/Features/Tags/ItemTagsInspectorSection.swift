import CitrationCore
import SwiftUI

struct ItemTagsInspectorSection: View {
    // MARK: Internal

    @Bindable var tags: TagsModel

    let item: BCItem

    var body: some View {
        Section("Tags") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("New tag", text: $tags.draft)
                    .onSubmit {
                        tags.addToSelectedItem()
                    }

                HStack {
                    if !availableTags.isEmpty {
                        Menu("Add Existing Tag…", systemImage: "tag") {
                            ForEach(availableTags, id: \.self) { tag in
                                Button(tag) {
                                    tags.draft = tag
                                    tags.addToSelectedItem()
                                }
                            }
                        }
                    }
                    Spacer()
                    Button("Add Tag", systemImage: "plus") {
                        tags.addToSelectedItem()
                    }
                    .disabled(tags.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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

    // MARK: Private

    private var availableTags: [String] {
        let existing = Set(item.tags.map { $0.lowercased() })
        let query = tags.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return tags.all.filter { tag in
            !existing.contains(tag.lowercased())
                && (query.isEmpty || tag.localizedCaseInsensitiveContains(query))
        }
    }
}
