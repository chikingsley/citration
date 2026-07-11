import CitrationCore
import SwiftUI

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
            Table(filteredItems, selection: $selectedItemIDs) {
                TableColumn("Title") { item in
                    Label(item.title.bcCollapsedWhitespace(), systemImage: "doc.text")
                }
                TableColumn("Creator") { item in
                    Text(authorSummary(for: item))
                }
                .width(min: 80, ideal: 160, max: 300)
                TableColumn("Year") { item in
                    Text(item.publicationYear.map(String.init) ?? "")
                }
                .width(min: 40, ideal: 60, max: 80)
                TableColumn("Tags") { item in
                    Text(item.tags.joined(separator: ", "))
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 140, max: 240)
            }
            .onChange(of: selectedItemIDs) { _, selection in
                onSelectionChange(selection)
            }
        }
    }

    // MARK: Private

    private func authorSummary(for item: BCItem) -> String {
        let names = item.creators.map(\.displayName).filter { !$0.isEmpty }
        guard let first = names.first else {
            return ""
        }
        if names.count > 1 {
            return "\(first) et al."
        }
        return first
    }
}
