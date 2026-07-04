import CitrationCore

extension AppModel {
    var selectedItemRecommendations: [LibraryRecommendation] {
        guard let selectedItem else {
            return []
        }
        return LibraryInsightEngine().recommendations(
            for: selectedItem,
            in: items,
            relationships: libraryRelationships
        )
    }

    func refreshSelectedItemDiscoverySuggestions() async {
        guard let selectedItem else {
            selectedItemDiscoverySuggestions = []
            isLoadingDiscoverySuggestions = false
            return
        }

        let selectedID = selectedItem.id
        isLoadingDiscoverySuggestions = true
        defer {
            if selectedItemID == selectedID {
                isLoadingDiscoverySuggestions = false
            }
        }

        do {
            let suggestions = try await relatedWorkDiscoveryProvider.suggestions(
                for: selectedItem,
                limit: 5
            )
            guard selectedItemID == selectedID else {
                return
            }
            selectedItemDiscoverySuggestions = suggestions
        }
        catch {
            guard selectedItemID == selectedID else {
                return
            }
            selectedItemDiscoverySuggestions = []
            statusMessage = "Failed to load related works"
        }
    }

    func importDiscoverySuggestion(_ suggestion: WorkDiscoverySuggestion) {
        Task {
            if let existing = existingItem(matching: suggestion) {
                selectItem(id: existing.id)
                statusMessage = "Selected existing related work"
                return
            }

            let item = suggestion.makeLibraryItem()
            await store.upsert(item)
            await refreshItems()
            selectItem(id: item.id)
            statusMessage = "Imported related work"
        }
    }

    private func existingItem(matching suggestion: WorkDiscoverySuggestion) -> BCItem? {
        let suggestionIdentifiers = Set(suggestion.identifiers)
        guard !suggestionIdentifiers.isEmpty else {
            return nil
        }

        return items.first { item in
            !Set(item.identifiers).isDisjoint(with: suggestionIdentifiers)
        }
    }
}
