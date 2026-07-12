import AppKit
import CitrationCore

extension AppModel {
    func performLibraryCommand(
        _ command: LibraryItemCommand,
        selection: Set<SynchronizedLibraryItemIdentity>
    ) {
        let identity = selectedItemIdentity.flatMap { selection.contains($0) ? $0 : nil }
            ?? items.first(where: { selection.contains($0.identity) })?.identity
            ?? selection.first

        switch command {
        case .open:
            if let identity {
                openPrimaryDocument(for: identity)
            }

        case let .addToCollection(collection):
            collections.addItems(ids: selection.map(\.appUUID), to: collection)

        case .copyBibTeX:
            copyBibTeX(selection: selection)

        case .moveToTrash:
            removeItems(ids: selection.map(\.appUUID))

        case .viewOnline:
            viewOnline(identity: identity)

        case .revealInFinder:
            revealInFinder(identity: identity)

        case .addAttachment,
             .addNote:
            break
        }
    }

    private func copyBibTeX(selection: Set<SynchronizedLibraryItemIdentity>) {
        let selectedItems = items
            .filter { selection.contains($0.identity) }
            .map(\.bibliographic)
        guard !selectedItems.isEmpty else {
            return
        }
        let text = CitationExporter().bibTeX(for: selectedItems)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = selectedItems.count == 1
            ? "Copied BibTeX"
            : "Copied \(selectedItems.count) BibTeX entries"
    }

    private func viewOnline(identity: SynchronizedLibraryItemIdentity?) {
        guard
            let identity,
            let item = items.first(where: { $0.identity == identity }),
            let url = item.bibliographic.onlineURL
        else {
            statusMessage = "No online location is available"
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func revealInFinder(identity: SynchronizedLibraryItemIdentity?) {
        guard let identity else {
            return
        }
        let database = database
        Task {
            let localURL = await Task.detached {
                let records = try? database.attachmentCacheRecords(
                    libraryID: identity.libraryID,
                    parentItemKey: identity.objectKey
                )
                return records?.compactMap(\.localURL).first
            }.value
            guard let localURL else {
                statusMessage = "No downloaded attachment is available"
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([localURL])
        }
    }
}

private extension BCItem {
    var onlineURL: URL? {
        for identifier in identifiers {
            let string = switch identifier.type {
            case .url: identifier.value
            case .doi: "https://doi.org/\(identifier.value)"
            case .arxiv: "https://arxiv.org/abs/\(identifier.value)"
            case .pmid: "https://pubmed.ncbi.nlm.nih.gov/\(identifier.value)"
            case .isbn: ""
            }
            if let url = string.isEmpty ? nil : URL(string: string) {
                return url
            }
        }
        return nil
    }
}
