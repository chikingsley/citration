import CitrationCore
import SwiftUI

struct ItemNotesInspectorSection: View {
    @Bindable var notes: NotesModel

    var body: some View {
        Section("Notes") {
            TextField("Add a note", text: $notes.draft, axis: .vertical)
                .lineLimit(2 ... 6)
                .onSubmit {
                    notes.addToSelectedItem()
                }

            HStack {
                Button("Add Note", systemImage: "note.text.badge.plus") {
                    notes.addToSelectedItem()
                }
                .disabled(notes.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }

            if notes.selectedItemNotes.isEmpty {
                Text("No notes")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notes.selectedItemNotes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(note.updatedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("v\(note.version) · \(note.identity.objectKey)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button {
                                notes.remove(note)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove note")
                        }

                        NoteHTMLView(html: note.html)
                            .frame(minHeight: 80, idealHeight: 140, maxHeight: 220)
                        if !note.tags.isEmpty {
                            Text(note.tags.map(\.value).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
