import SwiftUI
import CitrationCore

struct ItemNotesInspectorSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("Notes") {
            TextField("Add a note", text: $model.itemNoteDraft, axis: .vertical)
                .lineLimit(2...6)
                .onSubmit {
                    model.addNoteToSelectedItem()
                }

            HStack {
                Button("Add Note", systemImage: "note.text.badge.plus") {
                    model.addNoteToSelectedItem()
                }
                .disabled(model.itemNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }

            if model.selectedItemNotes.isEmpty {
                Text("No notes")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.selectedItemNotes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(note.updatedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                model.removeItemNote(note)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove note")
                        }

                        Text(note.text)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
