import CitrationCore
import PDFKit
import PencilKit
import SwiftUI

// MARK: - IPadPDFReaderView

struct IPadPDFReaderView: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    let item: SynchronizedLibraryItem
    let record: ZoteroAttachmentCacheRecord
    let url: URL

    var body: some View {
        IPadPDFRepresentable(
            url: url,
            progress: model.readerProgress,
            annotations: model.readerAnnotations,
            isInkMode: isInkMode,
            inkColor: inkColor,
            proxy: proxy,
            onPageChange: { pageNumber, pageCount in
                model.updateReaderProgress(
                    item: item,
                    record: record,
                    pageNumber: pageNumber,
                    pageCount: pageCount
                )
            },
            onInk: { anchor in
                Task {
                    await model.createPDFAnnotation(
                        item: item,
                        record: record,
                        anchor: anchor,
                        kind: .ink,
                        color: inkColor
                    )
                }
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(record.filename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Fit Page", systemImage: "arrow.up.left.and.arrow.down.right") {
                        proxy.fitPage()
                    }
                    Button("Continuous", systemImage: "rectangle.stack") {
                        proxy.useContinuousLayout()
                    }
                    Button("Fit Width", systemImage: "arrow.left.and.right") {
                        proxy.fitWidth()
                    }
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                }
                Menu {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        Button(color.rawValue.capitalized) {
                            inkColor = color
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                }
                Button(isInkMode ? "Stop Drawing" : "Draw", systemImage: isInkMode ? "pencil.slash" : "pencil.tip") {
                    isInkMode.toggle()
                }
                Button("Highlight", systemImage: "highlighter") {
                    addSelection(kind: .highlight)
                }
                Button("Underline", systemImage: "underline") {
                    addSelection(kind: .underline)
                }
                Button("Note", systemImage: "note.text.badge.plus") {
                    prepareNote()
                }
            }
        }
        .alert("Add PDF Note", isPresented: Binding(
            get: { pendingNoteSelection != nil },
            set: {
                if !$0 {
                    pendingNoteSelection = nil
                }
            }
        )) {
            TextField("Note", text: $noteDraft)
            Button("Cancel", role: .cancel) {
                pendingNoteSelection = nil
            }
            Button("Add") {
                addNote()
            }
            .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The note will use the current PDF text selection.")
        }
        .task {
            await model.openReader(item: item, record: record)
        }
    }

    // MARK: Private

    @State private var isInkMode = false
    @State private var inkColor: AnnotationColor = .yellow
    @State private var proxy: IPadPDFViewProxy = .init()
    @State private var pendingNoteSelection: (text: String, anchor: IPadPDFAnnotationAnchor)?
    @State private var noteDraft = ""

    private func addSelection(kind: AnnotationKind) {
        guard let selection = proxy.selection() else {
            model.statusMessage = "Select PDF text first"
            return
        }
        Task {
            await model.createPDFAnnotation(
                item: item,
                record: record,
                anchor: selection.anchor,
                kind: kind,
                color: inkColor,
                text: selection.text
            )
        }
    }

    private func prepareNote() {
        guard let selection = proxy.selection() else {
            model.statusMessage = "Select PDF text first"
            return
        }
        noteDraft = ""
        pendingNoteSelection = selection
    }

    private func addNote() {
        guard let selection = pendingNoteSelection else {
            return
        }
        let comment = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingNoteSelection = nil
        noteDraft = ""
        Task {
            await model.createPDFAnnotation(
                item: item,
                record: record,
                anchor: selection.anchor,
                kind: .note,
                color: inkColor,
                text: selection.text,
                comment: comment
            )
        }
    }
}
