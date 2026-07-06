import SwiftUI
import CitrationCore

struct ItemRelatedInspectorSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("Related") {
            if model.relatedItemCandidates.isEmpty {
                Text("Add another item to link related work.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Item", selection: $model.relatedItemTargetID) {
                    ForEach(model.relatedItemCandidates) { candidate in
                        Text(candidate.title.bcCollapsedWhitespace())
                            .tag(candidate.id as UUID?)
                    }
                }

                Picker("Kind", selection: $model.relatedItemKind) {
                    ForEach(LibraryRelationshipKind.allCases, id: \.self) { kind in
                        Text(kind.displayLabel).tag(kind)
                    }
                }

                TextField("Relationship note", text: $model.relatedItemNoteDraft, axis: .vertical)
                    .lineLimit(1...3)

                HStack {
                    Button("Add Link", systemImage: "link.badge.plus") {
                        model.addRelationshipToSelectedItem()
                    }
                    .disabled(model.relatedItemTargetID == nil)
                    Spacer()
                }
            }

            if !model.selectedItemRelationships.isEmpty {
                Divider()
                ForEach(model.selectedItemRelationships) { relationship in
                    relationshipRow(relationship)
                }
            }

            Divider()
            if model.selectedItemRecommendations.isEmpty {
                Text("No related local items yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.selectedItemRecommendations) { recommendation in
                    if let candidate = model.items.first(where: { $0.id == recommendation.candidateItemID }) {
                        recommendationRow(candidate: candidate, recommendation: recommendation)
                    }
                }
            }

            Divider()
            Text("OpenAlex")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !model.hasOpenAlexAPIKey {
                Text("OpenAlex key not configured.")
                    .foregroundStyle(.secondary)
            } else if model.isLoadingDiscoverySuggestions {
                ProgressView("Loading related works...")
            } else if model.selectedItemDiscoverySuggestions.isEmpty {
                Text("No OpenAlex suggestions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.selectedItemDiscoverySuggestions) { suggestion in
                    discoverySuggestionRow(suggestion)
                }
            }
        }
    }

    @ViewBuilder
    private func relationshipRow(_ relationship: LibraryRelationship) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.titleForRelatedItem(in: relationship))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    model.removeRelationship(relationship)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove link")
            }

            Text(relationship.kind.displayLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let note = relationship.note {
                Text(note)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func recommendationRow(
        candidate: BCItem,
        recommendation: LibraryRecommendation
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(candidate.title.bcCollapsedWhitespace())
                .font(.subheadline.weight(.medium))
            Text(recommendation.reasons.map(\.displayLabel).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func discoverySuggestionRow(_ suggestion: WorkDiscoverySuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(suggestion.title.bcCollapsedWhitespace())
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Import", systemImage: "square.and.arrow.down") {
                    model.importDiscoverySuggestion(suggestion)
                }
                .buttonStyle(.borderless)
            }

            Text(discoverySubtitle(for: suggestion))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(suggestion.reasons.map(\.displayLabel).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func discoverySubtitle(for suggestion: WorkDiscoverySuggestion) -> String {
        let creator = suggestion.creators.first?.displayName
        let year = suggestion.publicationYear.map(String.init)
        let pieces = [creator, year].compactMap { $0?.bcTrimmedNonEmpty }
        return pieces.isEmpty ? suggestion.providerName : pieces.joined(separator: " · ")
    }
}
