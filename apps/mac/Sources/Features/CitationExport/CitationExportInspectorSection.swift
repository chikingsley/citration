import CitrationCore
import SwiftUI

struct CitationExportInspectorSection: View {
    let citation: CitationModel

    var body: some View {
        Section("Citation") {
            Text(citation.preview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            HStack {
                Button("CSL JSON", systemImage: "doc.text") {
                    citation.exportSelected(format: .cslJSON)
                }
                Button("BibTeX", systemImage: "text.quote") {
                    citation.exportSelected(format: .bibTeX)
                }
                Spacer()
            }

            if !citation.exportText.isEmpty {
                Text(citation.exportText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}
