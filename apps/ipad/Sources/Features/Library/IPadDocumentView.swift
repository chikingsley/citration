import CitrationCore
import SwiftUI

// MARK: - IPadItemInfoView

struct IPadItemInfoView: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    let item: SynchronizedLibraryItem

    var body: some View {
        List {
            Section {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                if !item.creators.isEmpty {
                    Text(item.creators.map(\.displayName).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Type", value: item.zoteroItemType)
                if !item.zoteroDate.isEmpty {
                    LabeledContent("Date", value: item.zoteroDate)
                }
                if !item.publicationTitle.isEmpty {
                    LabeledContent("Publication", value: item.publicationTitle)
                }
                if !item.projected.abstractNote.isEmpty {
                    Text(item.projected.abstractNote)
                }
                metadata("DOI", item.projected.doi)
                metadata("ISBN", item.projected.isbn)
                metadata("ISSN", item.projected.issn)
                metadata("URL", item.projected.url)
                metadata("Language", item.projected.language)
                metadata("Rights", item.projected.rights)
                metadata("Extra", item.projected.extra)
            }
            if !item.tags.isEmpty {
                Section("Tags") {
                    Text(item.tags.joined(separator: ", "))
                }
            }
            Section("Notes") {
                if model.selectedNotes.isEmpty {
                    Text("No notes")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.selectedNotes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            IPadNoteHTMLView(html: note.html)
                                .frame(minHeight: 88, idealHeight: 140, maxHeight: 220)
                            HStack {
                                Text(note.updatedAt, style: .date)
                                Spacer()
                                Text("v\(note.version)")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @ViewBuilder
    private func metadata(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}

// MARK: - IPadDocumentView

struct IPadDocumentView: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    let item: SynchronizedLibraryItem
    let record: ZoteroAttachmentCacheRecord
    let url: URL

    var body: some View {
        documentContent
            .navigationTitle(record.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Library", systemImage: "chevron.left") {
                        model.closeDocument()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Info", systemImage: "info.circle") {
                        infoPresented = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .inspector(isPresented: $infoPresented) {
                IPadItemInfoView(model: model, item: item)
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
            }
    }

    // MARK: Private

    @State private var infoPresented = false

    @ViewBuilder
    private var documentContent: some View {
        switch DocumentFormat.infer(fileName: url.lastPathComponent, contentType: record.contentType) {
        case .pdf:
            IPadPDFReaderView(model: model, item: item, record: record, url: url)

        case .plainText:
            IPadPlainTextReaderView(model: model, item: item, record: record, url: url)

        case .epub:
            IPadEPUBReaderView(
                model: model,
                item: item,
                record: record,
                url: url
            )

        case .mobi:
            IPadMOBIReaderView(model: model, item: item, record: record, url: url)

        case .html:
            IPadWebDocumentView(
                url: url,
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
            .task(id: record.itemKey) {
                await model.openReader(item: item, record: record)
            }

        default:
            ContentUnavailableView("Unsupported Document", systemImage: "doc.questionmark")
        }
    }
}
