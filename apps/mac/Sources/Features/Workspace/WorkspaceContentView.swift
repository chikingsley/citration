import CitrationCore
import SwiftUI

struct WorkspaceContentView: View {
    // MARK: Internal

    @Bindable var model: AppModel
    let filteredItems: [SynchronizedLibraryItem]
    let emptyState: LibraryEmptyState
    @Binding var selectedItemIdentities: Set<SynchronizedLibraryItemIdentity>

    let downloadProgressByItemID: [UUID: Double]
    let collections: [LibraryCollection]

    let onSelectionChange: (Set<SynchronizedLibraryItemIdentity>) -> Void
    let onOpen: (Set<SynchronizedLibraryItemIdentity>) -> Void
    let onCommand: (LibraryItemCommand, Set<SynchronizedLibraryItemIdentity>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !model.documentSessions.isEmpty {
                WorkspaceTabBar(model: model, onDetach: detach)
                Divider()
            }
            workspaceContent
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow

    @ViewBuilder
    private var workspaceContent: some View {
        switch model.selectedWorkspaceTab {
        case .library:
            LibraryDetailView(
                filteredItems: filteredItems,
                emptyState: emptyState,
                selectedItemIdentities: $selectedItemIdentities,
                downloadProgressByItemID: downloadProgressByItemID,
                collections: collections,
                onSelectionChange: onSelectionChange,
                onOpen: onOpen,
                onCommand: onCommand
            )

        case let .document(attachmentKey):
            if let session = model.documentSessions.first(where: { $0.id == attachmentKey }) {
                ReaderPane(
                    attachment: session.attachment,
                    item: model.items.first { $0.identity.appUUID == session.attachment.itemID }?.bibliographic,
                    reader: session.reader,
                    onClose: {
                        model.closeDocument(attachmentKey: session.id)
                    },
                    onReturnToLibrary: {
                        model.selectWorkspaceTab(.library)
                    },
                    onDetach: {
                        detach(session.attachment)
                    }
                )
            } else {
                ContentUnavailableView(
                    "Document Unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("Return to the Library and open the document again.")
                )
            }
        }
    }

    private func detach(_ attachment: LocalAttachment) {
        openWindow(value: DocumentWindowRoute(attachment: attachment))
        model.closeDocument(attachmentKey: attachment.objectKey)
    }
}
