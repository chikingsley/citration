import CitrationCore
import Foundation

extension AppModel {
    func refreshSelectedAttachmentCacheRecords() {
        guard
            let libraryID = observedLibraryID,
            let itemKey = selectedLibraryItem?.identity.objectKey
        else {
            selectedAttachmentCacheRecords = []
            return
        }
        do {
            selectedAttachmentCacheRecords = try database.attachmentCacheRecords(
                libraryID: libraryID,
                parentItemKey: itemKey
            )
        } catch {
            selectedAttachmentCacheRecords = []
            statusMessage = "Failed to load attachment state"
        }
    }

    func retrySyncFailure(_ failure: ZoteroSyncFailureSummary) {
        guard let libraryID = observedLibraryID else {
            return
        }
        syncRecoveryOperationIDs.insert(failure.id)
        Task { @MainActor in
            defer { syncRecoveryOperationIDs.remove(failure.id) }
            do {
                try database.scheduleSyncFailureRetry(id: failure.id, libraryID: libraryID)
                if failure.operation == "attachment-download" {
                    _ = try await connectionManager.downloadAttachment(itemKey: failure.objectKey)
                    await importer.refreshSelectedItemAttachments()
                    refreshSelectedAttachmentCacheRecords()
                } else {
                    try await synchronizeRecovery()
                }
                statusMessage = "Recovery completed"
            } catch {
                statusMessage = "Recovery failed: \(error.localizedDescription)"
            }
        }
    }

    func retryAllSyncFailures() {
        guard let libraryID = observedLibraryID, let failures = syncStatus?.failures, !failures.isEmpty else {
            return
        }
        syncRecoveryOperationIDs.formUnion(failures.map(\.id))
        Task { @MainActor in
            defer { syncRecoveryOperationIDs.subtract(failures.map(\.id)) }
            do {
                try database.scheduleAllSyncFailureRetries(libraryID: libraryID)
                for failure in failures where failure.operation == "attachment-download" {
                    _ = try await connectionManager.downloadAttachment(itemKey: failure.objectKey)
                }
                try await synchronizeRecovery()
                await importer.refreshSelectedItemAttachments()
                refreshSelectedAttachmentCacheRecords()
                statusMessage = "All recoveries completed"
            } catch {
                statusMessage = "Recovery failed: \(error.localizedDescription)"
            }
        }
    }

    func resolveSyncConflict(
        _ failure: ZoteroSyncFailureSummary,
        resolution: ZoteroConflictResolution
    ) {
        guard let libraryID = observedLibraryID else {
            return
        }
        syncRecoveryOperationIDs.insert(failure.id)
        Task { @MainActor in
            defer { syncRecoveryOperationIDs.remove(failure.id) }
            do {
                try database.resolveConflict(
                    kind: failure.objectKind,
                    key: failure.objectKey,
                    resolution: resolution,
                    libraryID: libraryID
                )
                if resolution != .keepRemote {
                    try await synchronizeRecovery()
                }
                await refreshItems()
                statusMessage = "Conflict resolved"
            } catch {
                statusMessage = "Conflict resolution failed: \(error.localizedDescription)"
            }
        }
    }

    func downloadAttachment(_ record: ZoteroAttachmentCacheRecord) {
        guard !attachmentDownloadKeys.contains(record.itemKey) else {
            return
        }
        attachmentDownloadKeys.insert(record.itemKey)
        Task { @MainActor in
            defer { attachmentDownloadKeys.remove(record.itemKey) }
            do {
                _ = try await connectionManager.downloadAttachment(itemKey: record.itemKey)
                await importer.refreshSelectedItemAttachments()
                refreshSelectedAttachmentCacheRecords()
                statusMessage = "Downloaded \(record.filename)"
            } catch {
                refreshSelectedAttachmentCacheRecords()
                statusMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    private func synchronizeRecovery() async throws {
        guard let profile = zoteroSettings.profile else {
            throw ZoteroConnectionManagerError.missingCredential
        }
        if profile.canWrite {
            _ = try await connectionManager.synchronize()
        } else {
            _ = try await connectionManager.pullReadOnly()
        }
        await refreshItems()
    }
}
