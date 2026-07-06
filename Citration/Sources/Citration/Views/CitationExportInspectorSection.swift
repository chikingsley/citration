import CitrationCore
import SwiftUI

struct CitationExportInspectorSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("Citation") {
            Text(model.citationPreview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            HStack {
                Button("CSL JSON", systemImage: "doc.text") {
                    model.exportSelectedCitation(format: .cslJSON)
                }
                Button("BibTeX", systemImage: "text.quote") {
                    model.exportSelectedCitation(format: .bibTeX)
                }
                Spacer()
            }

            if !model.citationExportText.isEmpty {
                Text(model.citationExportText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}
