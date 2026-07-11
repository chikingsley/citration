import CitrationCore
import Foundation
import SwiftUI

// MARK: - ItemAttachmentsInspectorSection

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

            if
                model.importer.selectedItemAttachments.isEmpty,
                model.selectedAttachmentCacheRecords.isEmpty
            {
                Text("No cached attachments. Drop a file here or download a synchronized attachment.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.selectedAttachmentCacheRecords) { record in
                    if let attachment = localAttachment(for: record) {
                        attachmentRow(attachment)
                    } else {
                        attachmentCacheRow(record)
                    }
                }
                ForEach(unprojectedLocalAttachments) { attachment in
                    attachmentRow(attachment)
                }
            }
        }
    }

    // MARK: Private

    private var unprojectedLocalAttachments: [LocalAttachment] {
        let projectedKeys = Set(model.selectedAttachmentCacheRecords.map(\.itemKey))
        return model.importer.selectedItemAttachments.filter { !projectedKeys.contains($0.objectKey) }
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
                model.openDocument(attachment)
            } label: {
                Image(systemName: "book.pages")
            }
            .buttonStyle(.borderless)
            .disabled(!attachment.documentFormat.isSupportedInApp)
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

    private func attachmentCacheRow(_ record: ZoteroAttachmentCacheRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label(record.filename, systemImage: iconName(for: record.documentFormat))
                Text(record.cacheState.displayName)
                    .font(.caption)
                    .foregroundStyle(record.cacheState == .failed ? .red : .secondary)
                if let error = record.transferError?.bcTrimmedNonEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let localURL = record.localURL {
                Link("Cached File", destination: localURL)
            }
            Button(record.cacheState.actionTitle) {
                model.downloadAttachment(record)
            }
            .disabled(
                record.cacheState == .downloading
                    || model.attachmentDownloadKeys.contains(record.itemKey)
            )
        }
    }

    private func localAttachment(for record: ZoteroAttachmentCacheRecord) -> LocalAttachment? {
        model.importer.selectedItemAttachments.first { $0.objectKey == record.itemKey }
    }

    private func attachmentDetail(for attachment: LocalAttachment) -> String {
        let size = ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file)
        let format = attachment.documentFormat.displayName
        switch attachment.documentFormat {
        case .pdf,
             .epub,
             .html,
             .plainText:
            return "\(format) · In-app reader · \(size)"
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

private extension ZoteroAttachmentCacheRecord {
    var documentFormat: DocumentFormat {
        DocumentFormat.infer(fileName: filename, contentType: contentType)
    }
}

private extension ZoteroAttachmentCacheState {
    var displayName: String {
        switch self {
        case .notDownloaded: "Not Downloaded"
        case .downloading: "Downloading"
        case .downloaded: "Downloaded file unavailable"
        case .failed: "Download Failed"
        case .stale: "Cached File Is Stale"
        }
    }

    var actionTitle: String {
        switch self {
        case .notDownloaded: "Download"
        case .downloading: "Downloading…"
        case .downloaded,
             .failed: "Retry"
        case .stale: "Refresh"
        }
    }
}
