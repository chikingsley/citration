import CitrationCore
import SwiftUI

struct ItemRelatedInspectorSection: View {
    // MARK: Internal

    @Bindable var relationships: RelationshipsModel

    let model: AppModel

    var body: some View {
        Section("Related") {
            if relationships.candidates.isEmpty {
                Text("Add another item to link related work.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Item", selection: $relationships.targetID) {
                    ForEach(relationships.candidates) { candidate in
                        Text(candidate.title.bcCollapsedWhitespace())
                            .tag(candidate.id as UUID?)
                    }
                }

                Picker("Kind", selection: $relationships.kind) {
                    ForEach(LibraryRelationshipKind.allCases, id: \.self) { kind in
                        Text(kind.displayLabel).tag(kind)
                    }
                }

                TextField("Relationship note", text: $relationships.noteDraft, axis: .vertical)
                    .lineLimit(1 ... 3)

                HStack {
                    Button("Add Link", systemImage: "link.badge.plus") {
                        relationships.addToSelectedItem()
                    }
                    .disabled(relationships.targetID == nil)
                    Spacer()
                }
            }

            if !relationships.selectedItemRelationships.isEmpty {
                Divider()
                ForEach(relationships.selectedItemRelationships) { relationship in
                    relationshipRow(relationship)
                }
            }

            Divider()
            if model.insights.recommendations.isEmpty {
                Text("No related local items yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.insights.recommendations) { recommendation in
                    if let candidate = model.items.first(where: { $0.id == recommendation.candidateItemID }) {
                        recommendationRow(candidate: candidate, recommendation: recommendation)
                    }
                }
            }

            Divider()
            Text("OpenAlex")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !model.openAlexSettings.hasKey {
                Text("OpenAlex key not configured.")
                    .foregroundStyle(.secondary)
            } else if model.insights.isLoading {
                ProgressView("Loading related works...")
            } else if model.insights.suggestions.isEmpty {
                Text("No OpenAlex suggestions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.insights.suggestions) { suggestion in
                    discoverySuggestionRow(suggestion)
                }
            }
        }
    }

    // MARK: Private

    private func relationshipRow(_ relationship: LibraryRelationship) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(relationships.titleForRelatedItem(in: relationship))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    relationships.remove(relationship)
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

    private func discoverySuggestionRow(_ suggestion: WorkDiscoverySuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(suggestion.title.bcCollapsedWhitespace())
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Import", systemImage: "square.and.arrow.down") {
                    model.insights.importSuggestion(suggestion)
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
