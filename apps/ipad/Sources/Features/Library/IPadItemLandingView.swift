import CitrationCore
import SwiftUI

// MARK: - IPadItemLandingView

struct IPadItemLandingView: View {
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
            }

            Section("Documents") {
                if model.attachmentRecords.isEmpty {
                    ContentUnavailableView(
                        "No Readable Document",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Item information is still available from Info.")
                    )
                } else {
                    ForEach(model.attachmentRecords) { record in
                        HStack {
                            Label(record.filename, systemImage: documentIcon(record))
                            Spacer()
                            attachmentAction(record)
                        }
                    }
                }
            }
        }
        .navigationTitle("Read")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Info", systemImage: "info.circle") {
                    infoPresented = true
                }
            }
        }
        .sheet(isPresented: $infoPresented) {
            NavigationStack {
                IPadItemInfoView(model: model, item: item)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                infoPresented = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: Private

    @State private var infoPresented = false

    @ViewBuilder
    private func attachmentAction(_ record: ZoteroAttachmentCacheRecord) -> some View {
        switch record.cacheState {
        case .downloaded:
            Button("Open") {
                model.openDocumentChoice(record)
            }

        case .downloading:
            ProgressView()

        case .notDownloaded,
             .stale,
             .failed:
            Button(record.cacheState == .failed ? "Retry" : "Download") {
                model.openDocumentChoice(record)
            }
            .disabled(model.isWorking)
        }
    }

    private func documentIcon(_ record: ZoteroAttachmentCacheRecord) -> String {
        switch DocumentFormat.infer(fileName: record.filename, contentType: record.contentType) {
        case .pdf: "doc.richtext"
        case .epub: "book.closed"
        case .html: "globe"
        case .plainText: "doc.plaintext"
        default: "doc"
        }
    }
}

// MARK: - IPadItemInfoView

private struct IPadItemInfoView: View {
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
            .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
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
                    Button("Hide Controls", systemImage: "arrow.up.right.and.arrow.down.left") {
                        withAnimation {
                            chromeVisible = false
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if !chromeVisible {
                    Button("Show Controls", systemImage: "arrow.down.left.and.arrow.up.right") {
                        withAnimation {
                            chromeVisible = true
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .padding()
                    .accessibilityLabel("Show reader controls")
                }
            }
            .sheet(isPresented: $infoPresented) {
                NavigationStack {
                    IPadItemInfoView(model: model, item: item)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    infoPresented = false
                                }
                            }
                        }
                }
            }
    }

    // MARK: Private

    @State private var infoPresented = false
    @State private var chromeVisible = true

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
                url: url,
                chromeVisible: chromeVisible
            )

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
            .navigationTitle(record.filename)
            .task(id: record.itemKey) {
                await model.openReader(item: item, record: record)
            }

        default:
            ContentUnavailableView("Unsupported Document", systemImage: "doc.questionmark")
        }
    }
}
