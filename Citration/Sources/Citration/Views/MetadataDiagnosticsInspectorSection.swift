import SwiftUI
import CitrationCore

struct MetadataDiagnosticsInspectorSection: View {
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
            return "Title conflict"
        case .publicationYear:
            return "Year conflict"
        case .itemType:
            return "Item type conflict"
        }
    }
}
