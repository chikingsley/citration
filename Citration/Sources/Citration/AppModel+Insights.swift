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
}
