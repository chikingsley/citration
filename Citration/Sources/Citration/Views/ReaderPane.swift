import AppKit
import PDFKit
import SwiftUI
import CitrationCore

struct ReaderPane: View {
    let attachment: LocalAttachment
    let item: BCItem?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            readerContent
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
            }
            Spacer()
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
            PDFReaderView(url: attachment.localURL)
        case .epub:
            ContentUnavailableView(
                "EPUB Reader Pending",
                systemImage: "book",
                description: Text("Open externally until the Readium reader is wired.")
            )
        case .html, .plainText:
            ContentUnavailableView(
                "\(attachment.documentFormat.displayName) Reader Pending",
                systemImage: iconName(for: attachment.documentFormat),
                description: Text("Open externally for now.")
            )
        case .image, .audio, .unknown:
            ContentUnavailableView(
                "No Reader Available",
                systemImage: iconName(for: attachment.documentFormat),
                description: Text("Open externally for now.")
            )
        }
    }

    private func iconName(for format: DocumentFormat) -> String {
        switch format {
        case .pdf:
            return "doc.richtext"
        case .epub:
            return "book"
        case .html:
            return "safari"
        case .plainText:
            return "doc.plaintext"
        case .image:
            return "photo"
        case .audio:
            return "waveform"
        case .unknown:
            return "doc"
        }
    }
}

private struct PDFReaderView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .windowBackgroundColor
        loadDocument(in: pdfView, context: context)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        guard context.coordinator.loadedURL != url else {
            return
        }
        loadDocument(in: pdfView, context: context)
    }

    private func loadDocument(in pdfView: PDFView, context: Context) {
        pdfView.document = PDFDocument(url: url)
        context.coordinator.loadedURL = url
        pdfView.autoScales = true
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}
