import CitrationCore
import SwiftUI

// MARK: - MetadataDiagnosticsInspectorSection

struct MetadataDiagnosticsInspectorSection: View {
    // MARK: Internal

    @Bindable var model: AppModel

    var body: some View {
        Section("Metadata") {
            ForEach(model.metadataConflicts) { conflict in
                conflictRow(conflict)
            }

            ForEach(model.metadataWarnings.indices, id: \.self) { index in
                warningRow(model.metadataWarnings[index])
            }
        }
    }

    // MARK: Private

    private func conflictRow(_ conflict: MetadataResolutionConflict) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(conflict.field.displayName, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("\(conflict.preferredProvider): \(conflict.preferredValue)")
                .textSelection(.enabled)
            Text("\(conflict.alternateProvider): \(conflict.alternateValue)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }

    private func warningRow(_ warning: String) -> some View {
        Label {
            Text(warning)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .foregroundStyle(.secondary)
    }
}

private extension MetadataConflictField {
    var displayName: String {
        switch self {
        case .title:
            "Title conflict"
        case .publicationYear:
            "Year conflict"
        case .itemType:
            "Item type conflict"
        }
    }
}
