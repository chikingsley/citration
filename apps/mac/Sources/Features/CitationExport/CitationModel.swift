import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class CitationModel {
    // MARK: Lifecycle

    init(formatter: any CitationFormattingEngine) {
        self.formatter = formatter
    }

    // MARK: Internal

    var preview: String = "Select an item to preview citation output"
    var exportFormat: CitationExportFormat = .cslJSON
    var exportText: String = ""

    func bind(context: any LibraryContext) {
        self.context = context
    }

    func clearExport() {
        exportText = ""
    }

    func renderPreviewForSelection() async {
        guard let selectedItem = context?.selectedItem else {
            preview = "Select an item to preview citation output"
            return
        }

        do {
            let style = CitationStyle(id: "apa", title: "APA")
            let bibliography = try await formatter.formatBibliography(
                items: [selectedItem],
                style: style,
                options: CitationRenderOptions(format: .plainText)
            )
            guard let entry = bibliography.entries.first else {
                throw CitationEngineError.invalidInput("no bibliography entry")
            }
            preview = entry
        } catch {
            preview = "Citation preview failed: \(error.localizedDescription)"
        }
    }

    func exportSelected(format: CitationExportFormat) {
        exportFormat = format

        guard let selectedItem = context?.selectedItem else {
            exportText = ""
            context?.statusMessage = "Select an item first"
            return
        }

        do {
            let result = try CitationExporter().export(items: [selectedItem], format: format)
            exportText = result.text
            context?.statusMessage = "Prepared \(format.displayName)"
        } catch {
            exportText = ""
            context?.statusMessage = "Failed to export citation"
        }
    }

    // MARK: Private

    @ObservationIgnored private weak var context: (any LibraryContext)?

    private let formatter: any CitationFormattingEngine
}
