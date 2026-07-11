import CitrationCore
import SwiftUI

// MARK: - AnnotationEditorRow

struct AnnotationEditorRow: View {
    // MARK: Lifecycle

    init(
        annotation: SynchronizedLibraryAnnotation,
        onNavigate: @escaping () -> Void,
        onSave: @escaping (AnnotationKind, AnnotationColor, String, [ZoteroProjectedTag]) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.annotation = annotation
        self.onNavigate = onNavigate
        self.onSave = onSave
        self.onRemove = onRemove
        _kind = State(initialValue: annotation.kind ?? .note)
        _color = State(initialValue: annotation.compatibilityAnnotation().color)
        _comment = State(initialValue: annotation.comment)
        _tagText = State(initialValue: annotation.tags.map(\.value).joined(separator: "\n"))
    }

    // MARK: Internal

    let annotation: SynchronizedLibraryAnnotation
    let onNavigate: () -> Void
    let onSave: (AnnotationKind, AnnotationColor, String, [ZoteroProjectedTag]) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            heading
            Text("v\(annotation.version) · \(annotation.identity.objectKey)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            if annotation.kind == .ink {
                Text(inkDetail)
                    .foregroundStyle(.secondary)
            } else {
                editableContent
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    @State private var kind: AnnotationKind
    @State private var color: AnnotationColor
    @State private var comment: String
    @State private var tagText: String

    private var detail: String {
        let date = annotation.updatedAt.formatted(date: .abbreviated, time: .omitted)
        let type = annotation.type.capitalized
        if !annotation.pageLabel.isEmpty {
            return "\(type) · Page \(annotation.pageLabel) · \(date)"
        }
        return "\(type) · \(date)"
    }

    private var inkDetail: String {
        let width = annotation.inkWidth.map { String(format: "%.1f pt", $0) } ?? "unknown width"
        return "\(annotation.inkPaths.count) ink stroke(s) · \(width)"
    }

    private var projectedTags: [ZoteroProjectedTag] {
        normalizedTags.enumerated().map { position, value in
            let previous = annotation.tags.first {
                $0.value.localizedCaseInsensitiveCompare(value) == .orderedSame
            }
            return ZoteroProjectedTag(position: position, value: value, type: previous?.type)
        }
    }

    private var normalizedTags: [String] {
        var seen = Set<String>()
        return tagText.split(whereSeparator: \.isNewline).compactMap { substring in
            let value = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = value.lowercased()
            guard !value.isEmpty, seen.insert(normalized).inserted else {
                return nil
            }
            return value
        }
    }

    private var hasChanges: Bool {
        kind != annotation.kind
            || color != annotation.compatibilityAnnotation().color
            || comment != annotation.comment
            || projectedTags != annotation.tags
    }

    private var heading: some View {
        HStack {
            if annotation.kind != .note, annotation.kind != .ink {
                Circle()
                    .fill(Color(nsColor: color.nsColor))
                    .frame(width: 8, height: 8)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onNavigate) {
                Image(systemName: "arrow.forward.circle")
            }
            .buttonStyle(.borderless)
            .help("Go to annotation")
            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove annotation")
        }
    }

    private var editableContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !annotation.text.isEmpty {
                Text(annotation.text)
                    .textSelection(.enabled)
                    .italic(annotation.kind != .note)
            }
            HStack {
                if annotation.kind != .note {
                    Picker("Type", selection: $kind) {
                        Text("Highlight").tag(AnnotationKind.highlight)
                        Text("Underline").tag(AnnotationKind.underline)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 110)
                }
                Picker("Color", selection: $color) {
                    ForEach(AnnotationColor.allCases, id: \.self) { candidate in
                        Text(candidate.rawValue.capitalized).tag(candidate)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 100)
            }
            TextField("Comment", text: $comment, axis: .vertical)
                .lineLimit(1 ... 4)
            TextField("Tags, one per line", text: $tagText, axis: .vertical)
                .lineLimit(1 ... 4)
            Button("Save Annotation") {
                onSave(kind, color, comment, projectedTags)
            }
            .disabled(!hasChanges)
        }
    }
}
