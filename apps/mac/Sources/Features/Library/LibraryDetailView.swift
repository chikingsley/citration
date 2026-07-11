import CitrationCore
import SwiftUI

// MARK: - LibraryDetailView

struct LibraryDetailView: View {
    // MARK: Internal

    let filteredItems: [BCItem]
    let emptyState: LibraryEmptyState
    @Binding var selectedItemIDs: Set<UUID>

    let onSelectionChange: (Set<UUID>) -> Void

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
                selection: $selectedItemIDs,
                sortOrder: $sortOrder,
                columnCustomization: $columnCustomization
            ) {
                TableColumn("Title", value: \.title)
                    .customizationID("title")
                TableColumn("Creator", value: \BCItem.libraryCreatorSummary)
                    .width(min: 80, ideal: 160, max: 300)
                    .customizationID("creator")
                TableColumn("Year", value: \BCItem.libraryYear)
                    .width(min: 40, ideal: 60, max: 80)
                    .customizationID("year")
                TableColumn("Type", value: \BCItem.libraryTypeName)
                    .width(min: 70, ideal: 100, max: 150)
                    .customizationID("type")
                TableColumn("Tags", value: \BCItem.libraryTagSummary)
                    .width(min: 80, ideal: 140, max: 240)
                    .customizationID("tags")
                TableColumn("Modified", value: \BCItem.updatedAt) { item in
                    Text(item.updatedAt, format: .dateTime.year().month(.abbreviated).day())
                }
                .width(min: 80, ideal: 105, max: 140)
                .customizationID("modified")
            }
            .onChange(of: selectedItemIDs) { _, selection in
                onSelectionChange(selection)
            }
        }
    }

    // MARK: Private

    @SceneStorage("Citration.LibraryTableColumns") private var columnCustomization: TableColumnCustomization<BCItem>

    @State private var sortOrder = [KeyPathComparator(\BCItem.title)]

    private var sortedItems: [BCItem] {
        filteredItems.sorted(using: sortOrder)
    }
}

private extension BCItem {
    var libraryCreatorSummary: String {
        let names = creators.map(\.displayName).filter { !$0.isEmpty }
        guard let first = names.first else {
            return ""
        }
        return names.count > 1 ? "\(first) et al." : first
    }

    var libraryYear: String {
        publicationYear.map(String.init) ?? ""
    }

    var libraryTypeName: String {
        switch itemType {
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
        tags.joined(separator: ", ")
    }
}
