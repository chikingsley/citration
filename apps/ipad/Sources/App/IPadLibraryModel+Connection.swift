import CitrationCore
import Foundation

extension IPadLibraryModel {
    func connect(serverURLText: String, apiKey: String) async -> Bool {
        guard let serverURL = URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "Enter a valid server URL"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let profile = try await connectionManager.connect(serverURL: serverURL, apiKey: apiKey)
            _ = try await store.selectLibrary(identity: profile.libraryIdentity, name: profile.displayName)
            await reloadAll()
            statusMessage = "Connected as \(profile.displayName)"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func disconnect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await connectionManager.useLocalOnly()
            _ = try await store.selectLibrary(identity: .init(type: "local", remoteID: 0), name: "Local Library")
            await reloadAll()
            statusMessage = "Using local library"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func synchronize() async {
        guard !isWorking else {
            return
        }
        isWorking = true
        statusMessage = "Synchronizing"
        defer { isWorking = false }
        do {
            _ = try await connectionManager.synchronize()
            await reloadAll()
            statusMessage = "Up to date"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func download(_ record: ZoteroAttachmentCacheRecord) async {
        guard !isWorking else {
            return
        }
        isWorking = true
        statusMessage = "Downloading \(record.filename)"
        defer { isWorking = false }
        do {
            _ = try await connectionManager.downloadAttachment(itemKey: record.itemKey)
            await refreshAttachments()
            statusMessage = "Downloaded \(record.filename)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func retrySyncFailure(_ failure: ZoteroSyncFailureSummary) async {
        guard !recoveringFailureIDs.contains(failure.id) else {
            return
        }
        recoveringFailureIDs.insert(failure.id)
        defer { recoveringFailureIDs.remove(failure.id) }
        do {
            let libraryID = await store.selectedLibraryID()
            try database.scheduleSyncFailureRetry(id: failure.id, libraryID: libraryID)
            if failure.operation == "attachment-download" {
                _ = try await connectionManager.downloadAttachment(itemKey: failure.objectKey)
            } else {
                try await synchronizeRecovery()
            }
            await reloadAll()
            statusMessage = "Recovery completed"
        } catch {
            statusMessage = "Recovery failed: \(error.localizedDescription)"
        }
    }

    func retryAllSyncFailures() async {
        guard let failures = syncStatus?.failures, !failures.isEmpty else {
            return
        }
        recoveringFailureIDs.formUnion(failures.map(\.id))
        defer { recoveringFailureIDs.subtract(failures.map(\.id)) }
        do {
            let libraryID = await store.selectedLibraryID()
            try database.scheduleAllSyncFailureRetries(libraryID: libraryID)
            for failure in failures where failure.operation == "attachment-download" {
                _ = try await connectionManager.downloadAttachment(itemKey: failure.objectKey)
            }
            try await synchronizeRecovery()
            await reloadAll()
            statusMessage = "All recoveries completed"
        } catch {
            statusMessage = "Recovery failed: \(error.localizedDescription)"
        }
    }

    func resolveSyncConflict(
        _ failure: ZoteroSyncFailureSummary,
        resolution: ZoteroConflictResolution
    ) async {
        guard !recoveringFailureIDs.contains(failure.id) else {
            return
        }
        recoveringFailureIDs.insert(failure.id)
        defer { recoveringFailureIDs.remove(failure.id) }
        do {
            let libraryID = await store.selectedLibraryID()
            try database.resolveConflict(
                kind: failure.objectKind,
                key: failure.objectKey,
                resolution: resolution,
                libraryID: libraryID
            )
            if resolution != .keepRemote {
                try await synchronizeRecovery()
            }
            await reloadAll()
            statusMessage = "Conflict resolved"
        } catch {
            statusMessage = "Conflict resolution failed: \(error.localizedDescription)"
        }
    }

    private func synchronizeRecovery() async throws {
        switch configuration {
        case .localOnly:
            throw ZoteroConnectionManagerError.missingCredential
        case let .connected(profile):
            if profile.canWrite {
                _ = try await connectionManager.synchronize()
            } else {
                _ = try await connectionManager.pullReadOnly()
            }
        }
    }
}
