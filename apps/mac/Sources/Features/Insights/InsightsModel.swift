import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class InsightsModel {
    // MARK: Lifecycle

    init(discoveryProvider: any RelatedWorkDiscoveryProvider) {
        self.discoveryProvider = discoveryProvider
    }

    // MARK: Internal

    var suggestions: [WorkDiscoverySuggestion] = []
    var isLoading: Bool = false

    let discoveryProvider: any RelatedWorkDiscoveryProvider

    var recommendations: [LibraryRecommendation] {
        guard let context, let selectedItem = context.selectedItem, let relationships else {
            return []
        }
        return LibraryInsightEngine().recommendations(
            for: selectedItem,
            in: context.items,
            relationships: relationships.all
        )
    }

    func bind(context: any LibraryContext, relationships: RelationshipsModel) {
        self.context = context
        self.relationships = relationships
    }

    func clearForSelectionChange() {
        suggestions = []
    }

    func refreshForSelection() async {
        guard let context, let selectedItem = context.selectedItem else {
            suggestions = []
            isLoading = false
            return
        }

        let selectedID = selectedItem.id
        isLoading = true
        defer {
            if context.selectedItemID == selectedID {
                isLoading = false
            }
        }

        do {
            let fetched = try await discoveryProvider.suggestions(
                for: selectedItem,
                limit: 5
            )
            guard context.selectedItemID == selectedID else {
                return
            }
            suggestions = fetched
        } catch {
            guard context.selectedItemID == selectedID else {
                return
            }
            suggestions = []
            context.statusMessage = "Failed to load related works"
        }
    }

    func importSuggestion(_ suggestion: WorkDiscoverySuggestion) {
        Task {
            guard let context else {
                return
            }

            if let existing = existingItem(matching: suggestion) {
                context.selectItem(id: existing.id)
                context.statusMessage = "Selected existing related work"
                return
            }

            let item = suggestion.makeLibraryItem()
            await context.addItem(item)
            context.selectItem(id: item.id)
            context.statusMessage = "Imported related work"
        }
    }

    // MARK: Private

    @ObservationIgnored private weak var context: (any LibraryContext)?

    @ObservationIgnored private weak var relationships: RelationshipsModel?

    private func existingItem(matching suggestion: WorkDiscoverySuggestion) -> BCItem? {
        let suggestionIdentifiers = Set(suggestion.identifiers)
        guard !suggestionIdentifiers.isEmpty else {
            return nil
        }

        return context?.items.first { item in
            !Set(item.identifiers).isDisjoint(with: suggestionIdentifiers)
        }
    }
}
