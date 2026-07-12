import AppKit
import CitrationCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - ReaderPane

struct ReaderPane: View {
    // MARK: Internal

    let attachment: LocalAttachment
    let item: BCItem?
    let reader: ReaderModel
    let onClose: () -> Void
    let onReturnToLibrary: () -> Void
    let onDetach: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if attachment.documentFormat == .pdf {
                pdfControls
                Divider()
            }
            readerContent
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileExporter(
            isPresented: $exportPresented,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFileName,
            onCompletion: exportCompleted
        )
    }

    // MARK: Private

    @State private var exportPresented = false
    @State private var exportDocument: ReaderExportDocument?
    @State private var exportContentType: UTType = .data
    @State private var exportFileName = "Annotations"
    @State private var pdfSearchText = ""

    private let pdfProxy: PDFViewProxy = .init()

    private var progressDetail: String? {
        guard let progress = reader.progress else {
            return nil
        }

        if let fractionComplete = progress.fractionComplete {
            let percent = Int((fractionComplete * 100).rounded())
            return "\(progress.location.displayLabel) · \(percent)%"
        }
        return progress.location.displayLabel
    }

    private var pdfPageLabel: String {
        guard pdfProxy.currentPageNumber > 0, pdfProxy.pageCount > 0 else {
            return "— / —"
        }
        return "\(pdfProxy.currentPageNumber) / \(pdfProxy.pageCount)"
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onReturnToLibrary) {
                Image(systemName: "chevron.left")
            }
            .help("Return to Library")
            Image(systemName: iconName(for: attachment.documentFormat))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text(item?.title.bcCollapsedWhitespace() ?? attachment.documentFormat.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progressDetail {
                    Text(progressDetail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if attachment.documentFormat == .pdf {
                Menu {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        Button("\(color.rawValue.capitalized) Highlight") {
                            highlightSelection(color: color, kind: .highlight)
                        }
                    }
                    Divider()
                    Button("Underline") {
                        highlightSelection(color: .yellow, kind: .underline)
                    }
                } label: {
                    Image(systemName: "highlighter")
                }
                .help("Highlight selected text")

                Menu {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        Button("Draw in \(color.rawValue.capitalized)") {
                            reader.beginInk(color: color)
                        }
                    }
                    if reader.isInkMode {
                        Divider()
                        Button("Stop Drawing") {
                            reader.endInk()
                        }
                    }
                } label: {
                    Image(systemName: reader.isInkMode ? "pencil.tip.crop.circle.badge.plus" : "pencil.tip")
                }
                .help(reader.isInkMode ? "Drawing on the PDF" : "Draw on the PDF")
            }

            Menu {
                Button("Annotation Sidecar", systemImage: "doc.text") {
                    prepareSidecarExport()
                }
                if attachment.documentFormat == .pdf {
                    Button("Annotated PDF Copy", systemImage: "doc.richtext") {
                        prepareAnnotatedPDFExport()
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export annotations")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([attachment.localURL])
            } label: {
                Image(systemName: "folder")
            }
            .help("Show in Finder")

            Button {
                NSWorkspace.shared.open(attachment.localURL)
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .help("Open externally")

            if let onDetach {
                Button(action: onDetach) {
                    Image(systemName: "macwindow.badge.plus")
                }
                .help("Move to New Window")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Close reader")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var pdfControls: some View {
        HStack(spacing: 8) {
            Button(action: pdfProxy.goBackward) {
                Image(systemName: "chevron.left")
            }
            .disabled(!pdfProxy.canGoBackward)
            .help("Previous page")

            Text(pdfPageLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 72)

            Button(action: pdfProxy.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!pdfProxy.canGoForward)
            .help("Next page")

            Divider()
                .frame(height: 18)

            Button(action: pdfProxy.zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")
            Button(action: pdfProxy.zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
            Button(action: pdfProxy.fitPage) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit page")

            Menu {
                Button("Continuous Vertical") {
                    pdfProxy.setLayout(mode: .singlePageContinuous, direction: .vertical)
                }
                Button("Single Page") {
                    pdfProxy.setLayout(mode: .singlePage, direction: .horizontal)
                }
                Button("Two Pages") {
                    pdfProxy.setLayout(mode: .twoUp, direction: .horizontal)
                }
                Button("Wrapped Pages") {
                    pdfProxy.setLayout(mode: .twoUpContinuous, direction: .vertical)
                }
            } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .help("Page layout")

            Spacer()

            TextField("Find in document", text: $pdfSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(searchPDF)
            Button(action: searchPDF) {
                Image(systemName: "magnifyingglass")
            }
            .disabled(pdfSearchText.bcTrimmedNonEmpty == nil)
            .help("Find in document")
            Button(action: pdfProxy.findPrevious) {
                Image(systemName: "chevron.up")
            }
            .disabled(pdfProxy.searchResults.isEmpty)
            .help("Previous match")
            Button(action: pdfProxy.findNext) {
                Image(systemName: "chevron.down")
            }
            .disabled(pdfProxy.searchResults.isEmpty)
            .help("Next match")
            if pdfProxy.isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !pdfProxy.searchResults.isEmpty {
                Text("\(pdfProxy.currentSearchResult + 1)/\(pdfProxy.searchResults.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    @ViewBuilder
    private var readerContent: some View {
        switch attachment.documentFormat {
        case .pdf:
            PDFReaderView(
                attachment: attachment,
                progress: reader.progress,
                annotations: reader.annotations,
                proxy: pdfProxy,
                isInkMode: reader.isInkMode,
                inkColor: reader.inkColor,
                onInkStroke: reader.addInk,
                onProgressChange: reader.updateProgress
            )

        case .epub:
            EPUBReaderView(
                attachment: attachment,
                progress: reader.progress,
                annotations: reader.annotations,
                state: reader.epubState,
                onProgressChange: reader.updateProgress,
                onCreateAnnotation: reader.addEPUBAnnotation
            )

        case .mobi:
            ContentUnavailableView(
                "MOBI Reader Available on iPad",
                systemImage: "books.vertical",
                description: Text("Mac MOBI presentation will follow the shared parser acceptance.")
            )

        case .html:
            HTMLSnapshotReaderView(
                attachment: attachment,
                progress: reader.progress,
                onProgressChange: reader.updateProgress
            )

        case .plainText:
            PlainTextReaderView(
                attachment: attachment,
                progress: reader.progress,
                onProgressChange: reader.updateProgress
            )

        case .image,
             .audio,
             .unknown:
            ContentUnavailableView(
                "No Reader Available",
                systemImage: iconName(for: attachment.documentFormat),
                description: Text("Open externally for now.")
            )
        }
    }
}

private extension ReaderPane {
    private func highlightSelection(color: AnnotationColor, kind: AnnotationKind) {
        guard let selection = pdfProxy.selectionInfo() else {
            reader.reportMissingSelection()
            return
        }
        reader.addHighlight(
            selection: selection,
            color: color,
            kind: kind
        )
    }

    private func searchPDF() {
        guard let query = pdfSearchText.bcTrimmedNonEmpty else {
            return
        }
        pdfProxy.find(query)
    }

    private func prepareSidecarExport() {
        Task { @MainActor in
            do {
                let data = try await AnnotationExportService.sidecarData(
                    attachment: attachment,
                    annotations: reader.annotations
                )
                presentExport(
                    data: data,
                    contentType: .json,
                    fileName: "\(attachment.localURL.deletingPathExtension().lastPathComponent).annotations.json"
                )
            } catch {
                reader.context?.statusMessage = "Failed to prepare annotation sidecar"
            }
        }
    }

    private func prepareAnnotatedPDFExport() {
        do {
            let data = try AnnotationExportService.annotatedPDFData(
                attachment: attachment,
                annotations: reader.annotations
            )
            presentExport(
                data: data,
                contentType: .pdf,
                fileName: "\(attachment.localURL.deletingPathExtension().lastPathComponent).annotated.pdf"
            )
        } catch {
            reader.context?.statusMessage = "Failed to prepare annotated PDF"
        }
    }

    private func presentExport(data: Data, contentType: UTType, fileName: String) {
        exportDocument = ReaderExportDocument(data: data)
        exportContentType = contentType
        exportFileName = fileName
        exportPresented = true
    }

    private func exportCompleted(_ result: Result<URL, any Error>) {
        switch result {
        case let .success(url):
            reader.context?.statusMessage = "Exported \(url.lastPathComponent)"
        case .failure:
            reader.context?.statusMessage = "Export cancelled"
        }
        exportDocument = nil
    }

    private func iconName(for format: DocumentFormat) -> String {
        switch format {
        case .pdf:
            "doc.richtext"
        case .epub:
            "book"
        case .mobi:
            "books.vertical"
        case .html:
            "safari"
        case .plainText:
            "doc.plaintext"
        case .image:
            "photo"
        case .audio:
            "waveform"
        case .unknown:
            "doc"
        }
    }
}
