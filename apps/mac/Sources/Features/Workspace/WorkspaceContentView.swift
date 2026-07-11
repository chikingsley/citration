import CitrationCore
import SwiftUI

struct WorkspaceContentView: View {
    // MARK: Internal

    @Bindable var model: AppModel
    let filteredItems: [BCItem]
    let emptyState: LibraryEmptyState
    @Binding var selectedItemIDs: Set<UUID>

    let onSelectionChange: (Set<UUID>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabBar(model: model, onDetach: detach)
            Divider()
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
                selectedItemIDs: $selectedItemIDs,
                onSelectionChange: onSelectionChange
            )

        case let .document(attachmentKey):
            if let attachment = model.openDocuments.first(where: { $0.objectKey == attachmentKey }) {
                ReaderPane(
                    attachment: attachment,
                    item: model.items.first(where: { $0.id == attachment.itemID }),
                    reader: model.reader,
                    onClose: {
                        model.closeDocument(attachmentKey: attachment.objectKey)
                    },
                    onDetach: {
                        detach(attachment)
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
