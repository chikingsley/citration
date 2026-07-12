import CitrationCore
import SwiftUI

struct RootConfirmationDialogs: ViewModifier {
    // MARK: Internal

    @Bindable var model: AppModel
    @Binding var collectionPendingRemoval: LibraryCollection?
    @Binding var tagPendingRemoval: String?

    let removeCollection: (LibraryCollection) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Open Document",
                isPresented: readableAttachmentChoicesPresented,
                titleVisibility: .visible
            ) {
                ForEach(model.pendingReadableAttachmentChoices) { choice in
                    Button(choice.displayName) {
                        model.openReadableAttachment(choice)
                    }
                }
                Button("Cancel", role: .cancel) {
                    model.dismissReadableAttachmentChoices()
                }
            } message: {
                Text("Choose which attached document to open.")
            }
            .confirmationDialog(
                "Remove Collection?",
                isPresented: collectionRemovalPresented,
                titleVisibility: .visible,
                presenting: collectionPendingRemoval
            ) { collection in
                Button("Remove \(collection.name)", role: .destructive) {
                    removeCollection(collection)
                }
                Button("Cancel", role: .cancel) {
                    collectionPendingRemoval = nil
                }
            } message: { _ in
                Text("This removes the collection. Its library items remain available in All Items.")
            }
            .confirmationDialog(
                "Remove Tag from Library?",
                isPresented: tagRemovalPresented,
                titleVisibility: .visible,
                presenting: tagPendingRemoval
            ) { tag in
                Button("Remove \(tag)", role: .destructive) {
                    model.removeTagFromLibrary(tag)
                    tagPendingRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    tagPendingRemoval = nil
                }
            } message: { tag in
                Text("This removes \(tag) from every item that currently uses it.")
            }
    }

    // MARK: Private

    private var readableAttachmentChoicesPresented: Binding<Bool> {
        Binding(
            get: { !model.pendingReadableAttachmentChoices.isEmpty },
            set: { presented in
                if !presented {
                    model.dismissReadableAttachmentChoices()
                }
            }
        )
    }

    private var collectionRemovalPresented: Binding<Bool> {
        Binding(
            get: { collectionPendingRemoval != nil },
            set: { presented in
                if !presented {
                    collectionPendingRemoval = nil
                }
            }
        )
    }

    private var tagRemovalPresented: Binding<Bool> {
        Binding(
            get: { tagPendingRemoval != nil },
            set: { presented in
                if !presented {
                    tagPendingRemoval = nil
                }
            }
        )
    }
}
