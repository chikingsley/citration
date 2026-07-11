import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class RelationshipsModel {
    // MARK: Lifecycle

    init(store: any LibraryRelationshipStoring) {
        self.store = store
    }

    // MARK: Internal

    var all: [LibraryRelationship] = []
    var selectedItemRelationships: [LibraryRelationship] = []
    var targetID: UUID?
    var kind: LibraryRelationshipKind = .userLinked
    var noteDraft: String = ""

    let store: any LibraryRelationshipStoring

    /// Items the selected item could be linked to (everything but itself).
    var candidates: [BCItem] {
        guard let context, let selectedItemID = context.selectedItemID else {
            return []
        }
        return context.bibliographicItems.filter { $0.id != selectedItemID }
    }

    func bind(context: any LibraryContext) {
        self.context = context
    }

    func refresh() async {
        do {
            all = try await store.listRelationships()
            refreshForSelection()
        } catch {
            all = []
            selectedItemRelationships = []
            targetID = nil
            context?.statusMessage = "Failed to load related items"
        }
    }

    func refreshForSelection() {
        guard let selectedItemID = context?.selectedItemID else {
            selectedItemRelationships = []
            targetID = nil
            return
        }

        selectedItemRelationships = all
            .filter { relationship in
                relationship.sourceItemID == selectedItemID || relationship.targetItemID == selectedItemID
            }
            .sorted(by: sortForSelection)

        setDefaultTargetIfNeeded()
    }

    /// Clears per-selection draft state when the selected item changes.
    func clearSelectionDrafts() {
        targetID = nil
        noteDraft = ""
    }

    func addToSelectedItem() {
        guard let sourceItemID = context?.selectedItemID else {
            context?.statusMessage = "Select an item first"
            return
        }

        guard let targetItemID = targetID else {
            context?.statusMessage = "Select a related item first"
            return
        }

        guard sourceItemID != targetItemID else {
            context?.statusMessage = "Choose a different related item"
            return
        }

        let note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                _ = try await store.upsert(
                    LibraryRelationship(
                        sourceItemID: sourceItemID,
                        targetItemID: targetItemID,
                        kind: kind,
                        confidence: 1,
                        note: note
                    )
                )
                noteDraft = ""
                await refresh()
                context?.statusMessage = "Linked related item"
            } catch {
                context?.statusMessage = "Failed to link related item"
            }
        }
    }

    func remove(_ relationship: LibraryRelationship) {
        Task {
            do {
                try await store.remove(id: relationship.id)
                await refresh()
                context?.statusMessage = "Removed related item"
            } catch {
                context?.statusMessage = "Failed to remove related item"
            }
        }
    }

    /// Cascade cleanup when items are removed from the library.
    func removeItems(ids: [UUID]) async {
        try? await store.removeRelationships(itemIDs: ids)
        await refresh()
    }

    func titleForRelatedItem(in relationship: LibraryRelationship) -> String {
        let relatedID = relatedItemID(in: relationship)
        return context?.bibliographicItems.first { $0.id == relatedID }?.title.bcCollapsedWhitespace()
            ?? "Missing item"
    }

    // MARK: Private

    @ObservationIgnored private weak var context: (any LibraryContext)?

    private func relatedItemID(in relationship: LibraryRelationship) -> UUID {
        if relationship.sourceItemID == context?.selectedItemID {
            return relationship.targetItemID
        }
        return relationship.sourceItemID
    }

    private func setDefaultTargetIfNeeded() {
        let candidateIDs = Set(candidates.map(\.id))
        if
            let targetID,
            candidateIDs.contains(targetID)
        {
            return
        }

        targetID = candidates.first?.id
    }

    private func sortForSelection(
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
