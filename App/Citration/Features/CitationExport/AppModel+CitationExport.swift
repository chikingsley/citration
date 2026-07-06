import CitrationCore

extension AppModel {
    func exportSelectedCitation(format: CitationExportFormat) {
        citationExportFormat = format

        guard let selectedItem else {
            citationExportText = ""
            statusMessage = "Select an item first"
            return
        }

        do {
            let result = try CitationExporter().export(items: [selectedItem], format: format)
            citationExportText = result.text
            statusMessage = "Prepared \(format.displayName)"
        } catch {
            citationExportText = ""
            statusMessage = "Failed to export citation"
        }
    }
}
