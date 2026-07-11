import AppKit
import CitrationCore
import PDFKit
import SwiftUI
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
    }

    // MARK: Private

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
            }

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
                onProgressChange: reader.updateProgress
            )

        case .epub:
            EPUBReaderView(
                attachment: attachment,
                progress: reader.progress,
                onProgressChange: reader.updateProgress
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
            text: selection.text,
            pageNumber: selection.pageNumber,
            color: color,
            kind: kind
        )
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
