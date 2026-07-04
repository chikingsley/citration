import AppKit
import PDFKit
import SwiftUI
import WebKit
import CitrationCore

struct ReaderPane: View {
    let attachment: LocalAttachment
    let item: BCItem?
    let progress: ReaderProgress?
    let onProgressChange: (ReaderProgress) -> Void
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
                if let progressDetail {
                    Text(progressDetail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
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
            PDFReaderView(
                attachment: attachment,
                progress: progress,
                onProgressChange: onProgressChange
            )
        case .epub:
            EPUBReaderView(
                attachment: attachment,
                progress: progress,
                onProgressChange: onProgressChange
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

    private var progressDetail: String? {
        guard let progress else {
            return nil
        }

        if let fractionComplete = progress.fractionComplete {
            let percent = Int((fractionComplete * 100).rounded())
            return "\(progress.location.displayLabel) · \(percent)%"
        }
        return progress.location.displayLabel
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

private struct EPUBReaderView: NSViewRepresentable {
    let attachment: LocalAttachment
    let progress: ReaderProgress?
    let onProgressChange: (ReaderProgress) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        loadPublication(in: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedObjectKey != attachment.objectKey else {
            return
        }
        loadPublication(in: webView, context: context)
    }

    private func loadPublication(in webView: WKWebView, context: Context) {
        var didLoadPublication = false
        do {
            let publication = try EPUBPackageReader().publication(from: attachment.localURL)
            context.coordinator.removePublicationRoot()
            context.coordinator.loadedObjectKey = attachment.objectKey
            context.coordinator.publicationRoot = publication.rootDirectory
            webView.loadFileURL(
                publication.initialDocumentURL,
                allowingReadAccessTo: publication.rootDirectory
            )
            didLoadPublication = true
        }
        catch {
            context.coordinator.removePublicationRoot()
            context.coordinator.loadedObjectKey = attachment.objectKey
            webView.loadHTMLString(
                Self.errorHTML(message: error.localizedDescription),
                baseURL: nil
            )
        }

        if didLoadPublication, progress == nil {
            onProgressChange(
                ReaderProgress(
                    itemID: attachment.itemID,
                    attachmentKey: attachment.objectKey,
                    location: .epubCFI("epub-start"),
                    fractionComplete: nil
                )
            )
        }
    }

    private static func errorHTML(message: String) -> String {
        let escapedMessage = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {
              font: -apple-system-body;
              margin: 32px;
              color: #222;
              background: #fff;
            }
          </style>
        </head>
        <body>
          <h1>EPUB could not be opened</h1>
          <p>\(escapedMessage)</p>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject {
        var loadedObjectKey: String?
        var publicationRoot: URL?

        deinit {
            removePublicationRoot()
        }

        func removePublicationRoot() {
            if let publicationRoot {
                try? FileManager.default.removeItem(at: publicationRoot)
            }
            publicationRoot = nil
        }
    }
}

private struct PDFReaderView: NSViewRepresentable {
    let attachment: LocalAttachment
    let progress: ReaderProgress?
    let onProgressChange: (ReaderProgress) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        context.coordinator.configure(attachment: attachment, onProgressChange: onProgressChange)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .windowBackgroundColor
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        loadDocument(in: pdfView, context: context)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.configure(attachment: attachment, onProgressChange: onProgressChange)
        guard context.coordinator.loadedURL != attachment.localURL else {
            applyProgressIfNeeded(in: pdfView, context: context)
            return
        }
        loadDocument(in: pdfView, context: context)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewPageChanged,
            object: nsView
        )
    }

    private func loadDocument(in pdfView: PDFView, context: Context) {
        pdfView.document = PDFDocument(url: attachment.localURL)
        context.coordinator.loadedURL = attachment.localURL
        context.coordinator.appliedProgressToken = nil
        pdfView.autoScales = true
        applyProgressIfNeeded(in: pdfView, context: context)
    }

    private func applyProgressIfNeeded(in pdfView: PDFView, context: Context) {
        guard let progress,
              progress.attachmentKey == attachment.objectKey,
              context.coordinator.appliedProgressToken != token(for: progress),
              case .page(let pageNumber) = progress.location,
              let document = pdfView.document,
              document.pageCount > 0 else {
            return
        }

        let zeroBasedPage = min(max(pageNumber - 1, 0), document.pageCount - 1)
        guard let page = document.page(at: zeroBasedPage) else {
            return
        }

        context.coordinator.appliedProgressToken = token(for: progress)
        context.coordinator.isRestoringProgress = true
        pdfView.go(to: page)
        context.coordinator.isRestoringProgress = false
    }

    private func token(for progress: ReaderProgress) -> String {
        "\(progress.attachmentKey)|\(progress.location.displayLabel)|\(progress.updatedAt.timeIntervalSince1970)"
    }

    final class Coordinator: NSObject {
        var loadedURL: URL?
        var attachment: LocalAttachment?
        var onProgressChange: ((ReaderProgress) -> Void)?
        var appliedProgressToken: String?
        var isRestoringProgress = false

        func configure(
            attachment: LocalAttachment,
            onProgressChange: @escaping (ReaderProgress) -> Void
        ) {
            self.attachment = attachment
            self.onProgressChange = onProgressChange
        }

        @MainActor
        @objc
        func pageChanged(_ notification: Notification) {
            guard !isRestoringProgress,
                  let pdfView = notification.object as? PDFView,
                  let document = pdfView.document,
                  document.pageCount > 0,
                  let page = pdfView.currentPage,
                  let attachment else {
                return
            }

            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else {
                return
            }

            onProgressChange?(
                ReaderProgress(
                    itemID: attachment.itemID,
                    attachmentKey: attachment.objectKey,
                    location: .page(pageIndex + 1),
                    fractionComplete: Double(pageIndex + 1) / Double(document.pageCount)
                )
            )
        }
    }
}
