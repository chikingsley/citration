import CitrationCore
import Foundation
import SwiftUI

struct ItemAnnotationsInspectorSection: View {
    // MARK: Internal

    @Bindable var model: AppModel

    var body: some View {
        Section("Annotations") {
            if model.reader.activeAttachment?.itemID == model.selectedItemID {
                annotationEditor
            } else {
                ContentUnavailableView(
                    "No Open Document",
                    systemImage: "highlighter",
                    description: Text("Open an attachment to inspect or add its annotations.")
                )
            }
        }
    }

    // MARK: Private

    @ViewBuilder
    private var annotationEditor: some View {
        @Bindable var reader = model.reader

        TextField("Add a note", text: $reader.noteDraft, axis: .vertical)
            .lineLimit(2 ... 5)
        Button("Add Note", systemImage: "note.text.badge.plus") {
            model.reader.addNote()
        }
        .disabled(model.reader.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        if model.reader.annotations.isEmpty {
            Text("No annotations for this attachment yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(model.reader.annotations) { annotation in
                annotationRow(annotation)
            }
        }
    }

    private func annotationRow(_ annotation: LibraryAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if annotation.kind != .note {
                    Circle()
                        .fill(Color(nsColor: annotation.color.nsColor))
                        .frame(width: 8, height: 8)
                }
                Text(annotationDetail(for: annotation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.reader.removeAnnotation(annotation)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove annotation")
            }
            Text(annotationBody(for: annotation))
                .textSelection(.enabled)
                .italic(annotation.kind != .note)
        }
        .padding(.vertical, 4)
    }

    private func annotationDetail(for annotation: LibraryAnnotation) -> String {
        let date = annotation.updatedAt.formatted(date: .abbreviated, time: .omitted)
        if let location = annotation.location, annotation.kind != .note {
            return "\(location.displayLabel) · \(date)"
        }
        return date
    }

    private func annotationBody(for annotation: LibraryAnnotation) -> String {
        if annotation.kind == .note {
            return annotation.note
        }
        return annotation.selectedText ?? annotation.note
    }
}
