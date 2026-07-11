import CitrationCore
import Foundation
import SwiftUI

struct ItemAttachmentsInspectorSection: View {
    // MARK: Internal

    @Bindable var model: AppModel

    var body: some View {
        Section("Attachments") {
            let isProcessingThisItem = model.importer.reprocessingItemID == model.selectedItemID
            let isProcessingOtherItem = model.importer.reprocessingItemID != nil && !isProcessingThisItem

            Button(isProcessingThisItem ? "Processing..." : "Process Metadata") {
                model.importer.reprocessSelectedItemAttachments()
            }
            .disabled(
                isProcessingThisItem
                    || isProcessingOtherItem
                    || model.importer.isImporting
                    || model.importer.selectedItemAttachments.isEmpty
            )

            if model.importer.selectedItemAttachments.isEmpty {
                Text("No cached attachments. Drop a file here or download a synchronized attachment.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.importer.selectedItemAttachments) { attachment in
                    attachmentRow(attachment)
                }
            }
        }
    }

    // MARK: Private

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
                model.openDocument(attachment)
            } label: {
                Image(systemName: "book.pages")
            }
            .buttonStyle(.borderless)
            .disabled(!attachment.documentFormat.isReadableDocument)
            .help("Read in Citration")
            Link("Open", destination: attachment.localURL)
            Button {
                model.importer.removeAttachment(attachment)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove attachment")
        }
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
        case .pdf: "doc.richtext"
        case .epub: "book"
        case .html: "safari"
        case .plainText: "doc.plaintext"
        case .image: "photo"
        case .audio: "waveform"
        case .unknown: "doc"
        }
    }
}
