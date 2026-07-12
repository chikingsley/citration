import CitrationCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - RootInspectorView

struct RootInspectorView: View {
    // MARK: Internal

    @Bindable var model: AppModel

    let isAttachDropTargeted: Bool
    let attachDragBorderPhase: CGFloat
    let onTargetedChange: (Bool) -> Void
    let onDropURLs: ([URL]) -> Void

    var body: some View {
        inspectorContent
            .inspectorColumnWidth(min: 300, ideal: 360, max: 560)
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

    @State private var infoExpanded = true
    @State private var abstractExpanded = false
    @State private var attachmentsExpanded = true
    @State private var notesExpanded = false
    @State private var collectionsExpanded = false
    @State private var tagsExpanded = false
    @State private var relatedExpanded = false
    @State private var advancedExpanded = false

    @ViewBuilder
    private var inspectorContent: some View {
        if let item = model.selectedLibraryItemDetail {
            VStack(spacing: 0) {
                inspectorHeader(item)
                Divider()
                ScrollView {
                    Form {
                        DisclosureGroup("Info", isExpanded: $infoExpanded) {
                            ItemInfoInspectorSection(model: model, item: item)
                        }
                        DisclosureGroup("Abstract", isExpanded: $abstractExpanded) {
                            Text(item.projected.fields["abstractNote"]?.stringValue?.bcTrimmedNonEmpty
                                ?? "No abstract")
                                .foregroundStyle(item.projected.fields["abstractNote"] == nil ? .secondary : .primary)
                                .textSelection(.enabled)
                        }
                        DisclosureGroup("Attachments", isExpanded: $attachmentsExpanded) {
                            ItemAttachmentsInspectorSection(model: model)
                        }
                        DisclosureGroup("Notes", isExpanded: $notesExpanded) {
                            ItemNotesInspectorSection(notes: model.notes)
                        }
                        DisclosureGroup("Libraries and Collections", isExpanded: $collectionsExpanded) {
                            ItemCollectionsInspectorSection(model: model, item: item.bibliographic)
                        }
                        DisclosureGroup("Tags", isExpanded: $tagsExpanded) {
                            ItemTagsInspectorSection(tags: model.tags, item: item.bibliographic)
                        }
                        DisclosureGroup("Related", isExpanded: $relatedExpanded) {
                            ItemRelatedInspectorSection(relationships: model.relationships, model: model)
                        }
                        DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                            ItemAnnotationsInspectorSection(model: model)
                            CitationExportInspectorSection(citation: model.citation)
                            if model.importer.hasMetadataDiagnostics {
                                MetadataDiagnosticsInspectorSection(importer: model.importer)
                            }
                            LibraryDataInspectorSection(model: model, item: item)
                        }
                    }
                    .formStyle(.grouped)
                }
            }
        } else if let summary = model.selectedLibraryItemSummary {
            VStack(alignment: .leading, spacing: 12) {
                Text(summary.title)
                    .font(.headline)
                    .lineLimit(2)
                if !summary.creators.isEmpty {
                    Text(summary.creators.map(\.displayName).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                ProgressView("Loading item details…")
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select an item to view its details.")
            )
        }
    }

    private func inspectorHeader(_ item: SynchronizedLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.headline)
                .lineLimit(3)
            if !item.creators.isEmpty {
                Text(item.creators.map(\.displayName).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
