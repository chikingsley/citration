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

        if model.reader.activeAttachment?.documentFormat == .pdf {
            TextField("Add a note", text: $reader.noteDraft, axis: .vertical)
                .lineLimit(2 ... 5)
            Button("Add Note", systemImage: "note.text.badge.plus") {
                model.reader.addNote()
            }
            .disabled(model.reader.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else if model.reader.activeAttachment?.documentFormat == .epub {
            Text("Select text in the EPUB reader to create a synchronized highlight or underline.")
                .foregroundStyle(.secondary)
        } else {
            Text("Creating annotations is available for PDF and EPUB documents.")
                .foregroundStyle(.secondary)
        }

        if model.reader.annotations.isEmpty {
            Text("No annotations for this attachment yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(model.reader.annotations) { annotation in
                AnnotationEditorRow(
                    annotation: annotation,
                    onSave: { kind, color, comment, tags in
                        model.reader.updateAnnotation(
                            annotation,
                            kind: kind,
                            color: color,
                            comment: comment,
                            tags: tags
                        )
                    },
                    onRemove: {
                        model.reader.removeAnnotation(annotation)
                    }
                )
                .id(annotation)
            }
        }
    }
}
