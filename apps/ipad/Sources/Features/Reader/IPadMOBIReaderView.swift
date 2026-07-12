import CitrationCore
import SwiftUI

// MARK: - IPadMOBIReaderView

struct IPadMOBIReaderView: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    let item: SynchronizedLibraryItem
    let record: ZoteroAttachmentCacheRecord
    let url: URL

    var body: some View {
        Group {
            if let renderedURL {
                IPadWebDocumentView(
                    url: renderedURL,
                    format: .html,
                    progress: model.readerProgress,
                    onProgress: { offset, fraction in
                        model.updateTextProgress(
                            item: item,
                            record: record,
                            textOffset: offset,
                            fractionComplete: fraction
                        )
                    }
                )
            } else if let errorMessage {
                ContentUnavailableView(
                    "MOBI Could Not Be Opened",
                    systemImage: "books.vertical",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Opening MOBI…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: record.itemKey) {
            await model.openReader(item: item, record: record)
            await prepareDocument()
        }
        .onDisappear {
            removeRenderedDocument()
        }
    }

    // MARK: Private

    @State private var renderedURL: URL?
    @State private var errorMessage: String?

    private func prepareDocument() async {
        do {
            let sourceURL = url
            let document = try await Task.detached {
                try MOBIDocumentReader.read(from: sourceURL)
            }.value
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "citration-mobi-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appending(path: "book.html")
            try Data(document.html.utf8).write(to: destination, options: .atomic)
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: directory)
                return
            }
            renderedURL = destination
            errorMessage = nil
        } catch {
            renderedURL = nil
            errorMessage = error.localizedDescription
        }
    }

    private func removeRenderedDocument() {
        guard let renderedURL else {
            return
        }
        try? FileManager.default.removeItem(at: renderedURL.deletingLastPathComponent())
        self.renderedURL = nil
    }
}
