import CitrationCore
import SwiftUI

// MARK: - LibraryItemCommand

enum LibraryItemCommand {
    case addAttachment
    case addNote
    case addToCollection(LibraryCollection)
    case copyBibTeX
    case moveToTrash
    case open
    case revealInFinder
    case viewOnline
}

// MARK: - LibraryDetailView

struct LibraryDetailView: View {
    // MARK: Internal

    let filteredItems: [SynchronizedLibraryItem]
    let emptyState: LibraryEmptyState
    @Binding var selectedItemIdentities: Set<SynchronizedLibraryItemIdentity>

    let downloadProgressByItemID: [UUID: Double]
    let collections: [LibraryCollection]

    let onSelectionChange: (Set<SynchronizedLibraryItemIdentity>) -> Void
    let onOpen: (Set<SynchronizedLibraryItemIdentity>) -> Void
    let onCommand: (LibraryItemCommand, Set<SynchronizedLibraryItemIdentity>) -> Void

    var body: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView(
                emptyState.title,
                systemImage: emptyState.systemImage,
                description: Text(emptyState.description)
            )
        } else {
            Table(
                sortedItems,
                selection: $selectedItemIdentities,
                sortOrder: $sortOrder,
                columnCustomization: $columnCustomization
            ) {
                TableColumn("Title", value: \.libraryTitle) { item in
                    HStack(spacing: 8) {
                        Text(item.libraryTitle)
                        if let progress = downloadProgressByItemID[item.identity.appUUID] {
                            ProgressView(value: progress)
                                .frame(width: 54)
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .customizationID("title")
                TableColumn("Creator", value: \.libraryCreatorSummary)
                    .width(min: 80, ideal: 160, max: 300)
                    .customizationID("creator")
                TableColumn("Year", value: \.libraryYear)
                    .width(min: 40, ideal: 60, max: 80)
                    .customizationID("year")
                TableColumn("Type", value: \.libraryTypeName)
                    .width(min: 70, ideal: 100, max: 150)
                    .customizationID("type")
                TableColumn("Tags", value: \.libraryTagSummary)
                    .width(min: 80, ideal: 140, max: 240)
                    .customizationID("tags")
                TableColumn("Modified", value: \.libraryUpdatedAt) { item in
                    Text(item.libraryUpdatedAt, format: .dateTime.year().month(.abbreviated).day())
                }
                .width(min: 80, ideal: 105, max: 140)
                .customizationID("modified")
            }
            .onChange(of: selectedItemIdentities) { _, selection in
                onSelectionChange(selection)
            }
            .contextMenu(forSelectionType: SynchronizedLibraryItemIdentity.self) { selection in
                Button("Open", systemImage: "book.pages") {
                    onCommand(.open, selection)
                }
                .disabled(selection.isEmpty)
                Divider()
                Button("View Online", systemImage: "safari") {
                    onCommand(.viewOnline, selection)
                }
                .disabled(selection.count != 1)
                Button("Reveal in Finder", systemImage: "folder") {
                    onCommand(.revealInFinder, selection)
                }
                .disabled(selection.count != 1)
                Divider()
                Button("Add Note", systemImage: "note.text.badge.plus") {
                    onCommand(.addNote, selection)
                }
                .disabled(selection.count != 1)
                Button("Add Attachment…", systemImage: "paperclip") {
                    onCommand(.addAttachment, selection)
                }
                .disabled(selection.count != 1)
                Menu("Add to Collection", systemImage: "folder.badge.plus") {
                    ForEach(collections) { collection in
                        Button(collection.name) {
                            onCommand(.addToCollection(collection), selection)
                        }
                    }
                }
                .disabled(selection.isEmpty || collections.isEmpty)
                Divider()
                Button("Copy BibTeX", systemImage: "doc.on.doc") {
                    onCommand(.copyBibTeX, selection)
                }
                .disabled(selection.isEmpty)
                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    onCommand(.moveToTrash, selection)
                }
                .disabled(selection.isEmpty)
            } primaryAction: { selection in
                onOpen(selection)
            }
            .onKeyPress(.return) {
                guard !selectedItemIdentities.isEmpty else {
                    return .ignored
                }
                onOpen(selectedItemIdentities)
                return .handled
            }
        }
    }

    // MARK: Private

    @SceneStorage("Citration.LibraryTableColumns") private var columnCustomization: TableColumnCustomization<SynchronizedLibraryItem>

    @State private var sortOrder = [KeyPathComparator(\SynchronizedLibraryItem.libraryTitle)]

    private var sortedItems: [SynchronizedLibraryItem] {
        filteredItems.sorted(using: sortOrder)
    }
}

private extension SynchronizedLibraryItem {
    var libraryTitle: String {
        bibliographic.title
    }

    var libraryCreatorSummary: String {
        let names = bibliographic.creators.map(\.displayName).filter { !$0.isEmpty }
        guard let first = names.first else {
            return ""
        }
        return names.count > 1 ? "\(first) et al." : first
    }

    var libraryYear: String {
        bibliographic.publicationYear.map(String.init) ?? ""
    }

    var libraryTypeName: String {
        switch bibliographic.itemType {
        case .article:
            "Article"
        case .book:
            "Book"
        case .dataset:
            "Dataset"
        case .preprint:
            "Preprint"
        case .thesis:
            "Thesis"
        case .webpage:
            "Web Page"
        case .unknown:
            "Other"
        }
    }

    var libraryTagSummary: String {
        bibliographic.tags.joined(separator: ", ")
    }

    var libraryUpdatedAt: Date {
        bibliographic.updatedAt
    }
}
