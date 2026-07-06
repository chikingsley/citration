import CitrationCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct RootInspectorView: View {
    // MARK: Internal

    @Bindable var model: AppModel

    let isAttachDropTargeted: Bool
    let attachDragBorderPhase: CGFloat
    let onTargetedChange: (Bool) -> Void
    let onDropURLs: ([URL]) -> Void

    var body: some View {
        inspectorContent
            .inspectorColumnWidth(min: 240, ideal: 310, max: 450)
            .onDrop(
                of: [.fileURL],
                delegate: FileURLDropDelegate(
                    onTargetedChange: onTargetedChange,
                    onDropURLs: onDropURLs
                )
            )
            .overlay(alignment: .top) {
                if isAttachDropTargeted {
                    DropTargetBadge(
                        title: "Drop Here to Attach to Selected Item",
                        targeted: isAttachDropTargeted
                    )
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .overlay {
                if isAttachDropTargeted {
                    AttachmentDropOverlay(
                        targeted: isAttachDropTargeted,
                        dragBorderPhase: attachDragBorderPhase
                    )
                    .padding(8)
                    .transition(.opacity)
                }
            }
    }

    // MARK: Private

    @ViewBuilder
    private var inspectorContent: some View {
        if let item = model.selectedItem {
            ScrollView {
                Form {
                    itemInfoSection(item)
                    if model.hasMetadataDiagnostics {
                        MetadataDiagnosticsInspectorSection(model: model)
                    }
                    ItemTagsInspectorSection(tags: model.tags, item: item)
                    ItemCollectionsInspectorSection(model: model, item: item)
                    ItemNotesInspectorSection(notes: model.notes)
                    CitationExportInspectorSection(citation: model.citation)
                    attachmentsSection
                    if model.reader.activeAttachment?.itemID == item.id {
                        readerNotesSection
                    }
                    ItemRelatedInspectorSection(relationships: model.relationships, model: model)
                    OpenAlexSettingsInspectorSection(settings: model.settings)
                }
                .formStyle(.grouped)
            }
        } else {
            ScrollView {
                Form {
                    Section {
                        ContentUnavailableView(
                            "No Selection",
                            systemImage: "doc.text",
                            description: Text("Select an item to view its details.")
                        )
                    }
                    OpenAlexSettingsInspectorSection(settings: model.settings)
                }
                .formStyle(.grouped)
            }
        }
    }

    private var attachmentsSection: some View {
        Section("Attachments") {
            let isProcessingThisItem = model.reprocessingItemID == model.selectedItemID
            let isProcessingOtherItem = model.reprocessingItemID != nil && !isProcessingThisItem

            HStack {
                Button(isProcessingThisItem ? "Processing..." : "Process Metadata") {
                    model.reprocessSelectedItemAttachments()
                }
                .disabled(
                    isProcessingThisItem
                        || isProcessingOtherItem
                        || model.isImportingAttachments
                        || model.selectedItemAttachments.isEmpty
                )
                Spacer()
            }

            if model.selectedItemAttachments.isEmpty {
                Text("No attachments yet. Use Attach or drag a PDF into this sidebar.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.selectedItemAttachments) { attachment in
                    attachmentRow(attachment)
                }
            }
        }
    }

    private var readerNotesSection: some View {
        @Bindable var reader = model.reader
        return Section("Reader Notes") {
            TextField("Add a note", text: $reader.noteDraft, axis: .vertical)
                .lineLimit(2 ... 5)
            HStack {
                Button("Add Note", systemImage: "note.text.badge.plus") {
                    model.reader.addNote()
                }
                .disabled(model.reader.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }

            if model.reader.annotations.isEmpty {
                Text("No notes for this attachment yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.reader.annotations) { annotation in
                    readerAnnotationRow(annotation)
                }
            }
        }
    }

    private func itemInfoSection(_ item: BCItem) -> some View {
        Section("Info") {
            LabeledContent("Title") {
                Text(item.title.bcCollapsedWhitespace()).textSelection(.enabled)
            }
            if let doi = item.doi {
                LabeledContent("DOI") {
                    Text(doi).textSelection(.enabled)
                }
            }
            LabeledContent("Year", value: item.publicationYear.map(String.init) ?? "n.d.")
            LabeledContent("Creator", value: item.creators.first?.displayName ?? "Unknown")
            if item.creators.count > 1 {
                LabeledContent("Authors", value: item.creators.map(\.displayName).joined(separator: ", "))
            }
        }
    }

    private func attachmentRow(_ attachment: LocalAttachment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label(attachment.fileName, systemImage: iconName(for: attachment.documentFormat))
                Text(attachmentDetail(for: attachment))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.reader.open(attachment)
            } label: {
                Image(systemName: "book.pages")
            }
            .buttonStyle(.borderless)
            .disabled(!attachment.documentFormat.isReadableDocument)
            .help("Read in Citration")
            Link("Open", destination: attachment.localURL)
            Button {
                model.removeAttachment(attachment)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove attachment")
        }
    }

    private func readerAnnotationRow(_ annotation: LibraryAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(annotation.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.reader.removeAnnotation(annotation)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove note")
            }
            Text(annotation.note)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func attachmentDetail(for attachment: LocalAttachment) -> String {
        let size = ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file)
        let format = attachment.documentFormat.displayName
        switch attachment.documentFormat {
        case .pdf:
            return "\(format) · In-app reader · \(size)"
        case .epub,
             .html,
             .plainText:
            return "\(format) · Reader pending · \(size)"
        case .image,
             .audio,
             .unknown:
            return "\(format) · \(size)"
        }
    }

    private func iconName(for format: DocumentFormat) -> String {
        switch format {
        case .pdf:
            "doc.richtext"
        case .epub:
            "book"
        case .html:
            "safari"
        case .plainText:
            "doc.plaintext"
        case .image:
            "photo"
        case .audio:
            "waveform"
        case .unknown:
            "doc"
        }
    }
}
