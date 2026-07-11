import CitrationCore
import SwiftUI

struct ItemInfoInspectorSection: View {
    let item: BCItem

    var body: some View {
        Section("Info") {
            LabeledContent("Title") {
                Text(item.title.bcCollapsedWhitespace()).textSelection(.enabled)
            }
            if let doi = item.doi {
                LabeledContent("DOI") {
                    Text(doi).textSelection(.enabled)
                }
            }
            LabeledContent("Year", value: item.publicationYear.map(String.init) ?? "n.d.")
            LabeledContent("Creator", value: item.creators.first?.displayName ?? "Unknown")
            if item.creators.count > 1 {
                LabeledContent("Authors", value: item.creators.map(\.displayName).joined(separator: ", "))
            }
        }
    }
}
