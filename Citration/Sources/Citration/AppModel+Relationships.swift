import CitrationCore
import Foundation

extension AppModel {
    var relatedItemCandidates: [BCItem] {
        guard let selectedItemID else {
            return []
        }
        return items.filter { $0.id != selectedItemID }
    }

    func refreshRelationships() async {
        do {
            libraryRelationships = try await relationshipStore.listRelationships()
            await refreshSelectedItemRelationships()
        } catch {
            libraryRelationships = []
            selectedItemRelationships = []
            relatedItemTargetID = nil
            statusMessage = "Failed to load related items"
        }
    }

    func refreshSelectedItemRelationships() {
        guard let selectedItemID else {
            selectedItemRelationships = []
            relatedItemTargetID = nil
            return
        }

        selectedItemRelationships = libraryRelationships
            .filter { relationship in
                relationship.sourceItemID == selectedItemID || relationship.targetItemID == selectedItemID
            }
            .sorted(by: sortRelationshipsForSelection)

        setDefaultRelatedItemTargetIfNeeded()
    }

    func addRelationshipToSelectedItem() {
        guard let sourceItemID = selectedItemID else {
            statusMessage = "Select an item first"
            return
        }

        guard let targetItemID = relatedItemTargetID else {
            statusMessage = "Select a related item first"
            return
        }

        guard sourceItemID != targetItemID else {
            statusMessage = "Choose a different related item"
            return
        }

        let note = relatedItemNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                _ = try await relationshipStore.upsert(
                    LibraryRelationship(
                        sourceItemID: sourceItemID,
                        targetItemID: targetItemID,
                        kind: relatedItemKind,
                        confidence: 1,
                        note: note
                    )
                )
                relatedItemNoteDraft = ""
                await refreshRelationships()
                statusMessage = "Linked related item"
            } catch {
                statusMessage = "Failed to link related item"
            }
        }
    }

    func removeRelationship(_ relationship: LibraryRelationship) {
        Task {
            do {
                try await relationshipStore.remove(id: relationship.id)
                await refreshRelationships()
                statusMessage = "Removed related item"
            } catch {
                statusMessage = "Failed to remove related item"
            }
        }
    }

    func titleForRelatedItem(in relationship: LibraryRelationship) -> String {
        let relatedID = relatedItemID(in: relationship)
        return items.first { $0.id == relatedID }?.title.bcCollapsedWhitespace() ?? "Missing item"
    }

    private func relatedItemID(in relationship: LibraryRelationship) -> UUID {
        if relationship.sourceItemID == selectedItemID {
            return relationship.targetItemID
        }
        return relationship.sourceItemID
    }

    private func setDefaultRelatedItemTargetIfNeeded() {
        let candidateIDs = Set(relatedItemCandidates.map(\.id))
        if
            let relatedItemTargetID,
            candidateIDs.contains(relatedItemTargetID)
        {
            return
        }

        relatedItemTargetID = relatedItemCandidates.first?.id
    }

    private func sortRelationshipsForSelection(
        _ lhs: LibraryRelationship,
        _ rhs: LibraryRelationship
    ) -> Bool {
        if lhs.kind.rawValue == rhs.kind.rawValue {
            return titleForRelatedItem(in: lhs).localizedCaseInsensitiveCompare(
                titleForRelatedItem(in: rhs)
            ) == .orderedAscending
        }
        return lhs.kind.displayLabel.localizedCaseInsensitiveCompare(rhs.kind.displayLabel) == .orderedAscending
    }
}
