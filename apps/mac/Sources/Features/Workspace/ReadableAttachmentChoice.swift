import CitrationCore
import Foundation

// MARK: - ReadableAttachmentChoice

struct ReadableAttachmentChoice: Identifiable, Hashable {
    let itemID: UUID
    let record: ZoteroAttachmentCacheRecord?
    let localAttachment: LocalAttachment?

    var id: String {
        localAttachment?.objectKey ?? record?.itemKey ?? "\(itemID.uuidString)-missing"
    }

    var displayName: String {
        localAttachment?.fileName ?? record?.filename ?? "Document"
    }

    var documentFormat: DocumentFormat {
        if let localAttachment {
            return localAttachment.documentFormat
        }
        guard let record else {
            return .unknown
        }
        return DocumentFormat.infer(fileName: record.filename, contentType: record.contentType)
    }
}

// MARK: - AppModel + Primary Document

extension AppModel {
    func openPrimaryDocument(for identity: SynchronizedLibraryItemIdentity) {
        Task { @MainActor in
            do {
                let choices = try await readableAttachmentChoices(for: identity)
                switch choices.count {
                case 0:
                    statusMessage = "No readable document is attached"

                case 1:
                    if let choice = choices.first {
                        openReadableAttachment(choice)
                    }

                default:
                    pendingReadableAttachmentChoices = choices
                }
            } catch {
                statusMessage = "Failed to inspect attached documents"
            }
        }
    }

    func openReadableAttachment(_ choice: ReadableAttachmentChoice) {
        pendingReadableAttachmentChoices = []
        if
            let attachment = choice.localAttachment,
            FileManager.default.fileExists(atPath: attachment.localURL.path)
        {
            openDocument(attachment)
            return
        }
        guard let record = choice.record else {
            statusMessage = "Document file is unavailable"
            return
        }
        downloadAndOpen(record, itemID: choice.itemID)
    }

    func dismissReadableAttachmentChoices() {
        pendingReadableAttachmentChoices = []
    }

    // MARK: Private

    private func readableAttachmentChoices(
        for identity: SynchronizedLibraryItemIdentity
    ) async throws -> [ReadableAttachmentChoice] {
        let localAttachments = try await attachmentStore.listAttachments(for: identity.appUUID)
        let localByKey = Dictionary(uniqueKeysWithValues: localAttachments.map { ($0.objectKey, $0) })
        let records = try database.attachmentCacheRecords(
            libraryID: identity.libraryID,
            parentItemKey: identity.objectKey
        )
        var choices = records.compactMap { record -> ReadableAttachmentChoice? in
            let choice = ReadableAttachmentChoice(
                itemID: identity.appUUID,
                record: record,
                localAttachment: localByKey[record.itemKey]
            )
            return choice.documentFormat.isSupportedInApp ? choice : nil
        }
        let projectedKeys = Set(records.map(\.itemKey))
        choices += localAttachments.compactMap { attachment in
            guard !projectedKeys.contains(attachment.objectKey), attachment.documentFormat.isSupportedInApp else {
                return nil
            }
            return ReadableAttachmentChoice(
                itemID: identity.appUUID,
                record: nil,
                localAttachment: attachment
            )
        }
        return choices.sorted(by: compareReadableAttachments)
    }

    private func compareReadableAttachments(
        _ lhs: ReadableAttachmentChoice,
        _ rhs: ReadableAttachmentChoice
    ) -> Bool {
        let leftPriority = readableFormatPriority(lhs.documentFormat)
        let rightPriority = readableFormatPriority(rhs.documentFormat)
        if leftPriority == rightPriority {
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return leftPriority < rightPriority
    }

    private func readableFormatPriority(_ format: DocumentFormat) -> Int {
        switch format {
        case .pdf: 0
        case .epub: 1
        case .html: 2
        case .plainText: 3
        case .image: 4
        case .audio: 5
        case .unknown: 6
        }
    }

    private func downloadAndOpen(_ record: ZoteroAttachmentCacheRecord, itemID: UUID) {
        guard !attachmentDownloadKeys.contains(record.itemKey) else {
            return
        }
        attachmentDownloadKeys.insert(record.itemKey)
        statusMessage = "Downloading \(record.filename)…"
        Task { @MainActor in
            defer { attachmentDownloadKeys.remove(record.itemKey) }
            do {
                _ = try await connectionManager.downloadAttachment(itemKey: record.itemKey)
                await importer.refreshSelectedItemAttachments()
                refreshSelectedAttachmentCacheRecords()
                let attachments = try await attachmentStore.listAttachments(for: itemID)
                guard let attachment = attachments.first(where: { $0.objectKey == record.itemKey }) else {
                    statusMessage = "Downloaded file is unavailable"
                    return
                }
                openDocument(attachment)
            } catch {
                refreshSelectedAttachmentCacheRecords()
                statusMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}
