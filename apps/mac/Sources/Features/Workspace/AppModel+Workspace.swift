import CitrationCore
import Foundation

extension AppModel {
    func openDocument(_ attachment: LocalAttachment) {
        if let index = documentSessions.firstIndex(where: { $0.id == attachment.objectKey }) {
            documentSessions[index].attachment = attachment
        } else {
            let reader = makeReaderModel()
            reader.open(attachment)
            documentSessions.append(DocumentSession(attachment: attachment, reader: reader))
        }
        selectWorkspaceTab(.document(attachment.objectKey))
    }

    func selectWorkspaceTab(_ tab: WorkspaceTab) {
        switch tab {
        case .library:
            selectedWorkspaceTab = .library

        case let .document(attachmentKey):
            guard let session = documentSessions.first(where: { $0.id == attachmentKey }) else {
                selectedWorkspaceTab = .library
                return
            }
            selectedWorkspaceTab = tab
            session.reader.open(session.attachment)
        }
    }

    func closeDocument(attachmentKey: String) {
        guard let index = documentSessions.firstIndex(where: { $0.id == attachmentKey }) else {
            return
        }
        let wasSelected = selectedWorkspaceTab == .document(attachmentKey)
        let removed = documentSessions.remove(at: index)
        removed.reader.clear()
        guard wasSelected else {
            return
        }
        if documentSessions.isEmpty {
            selectWorkspaceTab(.library)
        } else {
            let nextIndex = min(index, documentSessions.index(before: documentSessions.endIndex))
            selectWorkspaceTab(.document(documentSessions[nextIndex].id))
        }
    }

    func closeAllDocuments() {
        let keys = documentSessions.map(\.id)
        for key in keys {
            closeDocument(attachmentKey: key)
        }
        selectedWorkspaceTab = .library
    }

    func handleAttachmentRemoved(_ attachment: LocalAttachment) async {
        if let session = documentSessions.first(where: { $0.id == attachment.objectKey }) {
            await session.reader.handleAttachmentRemoved(attachment)
            closeDocument(attachmentKey: attachment.objectKey)
        } else {
            await libraryReader.handleAttachmentRemoved(attachment)
        }
    }

    func reconcileOpenDocuments(itemID: UUID, availableAttachments: [LocalAttachment]) {
        let availableKeys = Set(availableAttachments.map(\.objectKey))
        let missingKeys = documentSessions
            .filter { $0.attachment.itemID == itemID && !availableKeys.contains($0.id) }
            .map(\.id)
        for key in missingKeys {
            closeDocument(attachmentKey: key)
        }
    }

    func makeReaderModel() -> ReaderModel {
        let model = ReaderModel(progressStore: readerProgressStore, annotationStore: annotationStore)
        model.bind(context: self)
        return model
    }
}
