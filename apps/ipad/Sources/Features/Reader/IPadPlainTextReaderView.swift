import CitrationCore
import SwiftUI
import UIKit

// MARK: - IPadPlainTextReaderView

struct IPadPlainTextReaderView: View {
    @Bindable var model: IPadLibraryModel

    let item: SynchronizedLibraryItem
    let record: ZoteroAttachmentCacheRecord
    let url: URL

    var body: some View {
        IPadPlainTextRepresentable(
            url: url,
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
        .navigationTitle(record.filename)
        .task(id: record.itemKey) {
            await model.openReader(item: item, record: record)
        }
    }
}

// MARK: - IPadPlainTextRepresentable

private struct IPadPlainTextRepresentable: UIViewRepresentable {
    // MARK: Internal

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        // MARK: Lifecycle

        init(parent: IPadPlainTextRepresentable) {
            self.parent = parent
        }

        // MARK: Internal

        var parent: IPadPlainTextRepresentable
        var loadedURL: URL?
        var didRestoreProgress = false
        var isRestoring = false
        var progressTask: Task<Void, Never>?

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard loadedURL != nil, !isRestoring else {
                return
            }
            progressTask?.cancel()
            progressTask = Task { [weak self, weak scrollView] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, let scrollView else {
                    return
                }
                let maximumOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
                let fraction = maximumOffset > 0 ? min(max(scrollView.contentOffset.y / maximumOffset, 0), 1) : 0
                let length = (scrollView as? UITextView)?.text.utf16.count ?? 0
                parent.onProgress(Int(Double(length) * fraction), fraction)
            }
        }
    }

    let url: URL
    let progress: ReaderProgress?
    let onProgress: (Int, Double) -> Void

    static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        coordinator.progressTask?.cancel()
        textView.delegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
        textView.backgroundColor = .systemBackground
        load(in: textView, coordinator: context.coordinator)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedURL != url {
            load(in: textView, coordinator: context.coordinator)
        }
        restoreProgress(in: textView, coordinator: context.coordinator)
    }

    // MARK: Private

    private func load(in textView: UITextView, coordinator: Coordinator) {
        coordinator.loadedURL = url
        coordinator.didRestoreProgress = false
        do {
            textView.text = try CachedPlainTextDocument(fileURL: url).text
            textView.textColor = .label
        } catch {
            textView.text = "Text document could not be opened.\n\n\(error.localizedDescription)"
            textView.textColor = .secondaryLabel
        }
    }

    private func restoreProgress(in textView: UITextView, coordinator: Coordinator) {
        guard !coordinator.didRestoreProgress else {
            return
        }
        coordinator.didRestoreProgress = true
        textView.layoutIfNeeded()
        let maximumOffset = max(textView.contentSize.height - textView.bounds.height, 0)
        coordinator.isRestoring = true
        textView.setContentOffset(
            CGPoint(x: 0, y: maximumOffset * CGFloat(progress?.fractionComplete ?? 0)),
            animated: false
        )
        coordinator.isRestoring = false
    }
}
