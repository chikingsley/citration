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

    @SceneStorage("Citration.ItemInspectorSection") private var selectedSectionRawValue =
        ItemInspectorSection.info.rawValue

    @ViewBuilder
    private var inspectorContent: some View {
        if let item = model.selectedLibraryItem {
            VStack(spacing: 0) {
                sectionPicker
                Divider()
                ScrollView {
                    Form {
                        selectedContent(item)
                    }
                    .formStyle(.grouped)
                }
            }
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select an item to view its details.")
            )
        }
    }

    private var sectionPicker: some View {
        Picker("Inspector", selection: $selectedSectionRawValue) {
            ForEach(ItemInspectorSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(section.rawValue)
                    .help(section.title)
            }
        }
        .pickerStyle(.segmented)
        .padding(10)
    }

    @ViewBuilder
    private func selectedContent(_ item: SynchronizedLibraryItem) -> some View {
        switch ItemInspectorSection(rawValue: selectedSectionRawValue) ?? .info {
        case .info:
            ItemInfoInspectorSection(model: model, item: item)
            if model.importer.hasMetadataDiagnostics {
                MetadataDiagnosticsInspectorSection(importer: model.importer)
            }
            ItemTagsInspectorSection(tags: model.tags, item: item.bibliographic)
            ItemCollectionsInspectorSection(model: model, item: item.bibliographic)

        case .attachments:
            ItemAttachmentsInspectorSection(model: model)

        case .notes:
            ItemNotesInspectorSection(notes: model.notes)

        case .annotations:
            ItemAnnotationsInspectorSection(model: model)

        case .cite:
            CitationExportInspectorSection(citation: model.citation)

        case .related:
            ItemRelatedInspectorSection(relationships: model.relationships, model: model)

        case .data:
            LibraryDataInspectorSection(model: model, item: item)
        }
    }
}

// MARK: - ItemInspectorSection

private enum ItemInspectorSection: String, CaseIterable, Identifiable {
    case info
    case attachments
    case notes
    case annotations
    case cite
    case related
    case data

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .info: "Info"
        case .attachments: "Attachments"
        case .notes: "Notes"
        case .annotations: "Annotations"
        case .cite: "Cite"
        case .related: "Related"
        case .data: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle"
        case .attachments: "paperclip"
        case .notes: "note.text"
        case .annotations: "highlighter"
        case .cite: "quote.opening"
        case .related: "point.3.connected.trianglepath.dotted"
        case .data: "externaldrive.badge.checkmark"
        }
    }
}
