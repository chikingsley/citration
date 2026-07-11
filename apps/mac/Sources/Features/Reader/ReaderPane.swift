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
    let onDetach: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
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

    private var header: some View {
        HStack(spacing: 10) {
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
