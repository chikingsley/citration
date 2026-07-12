import CitrationCore
import Foundation

extension AppModel {
    func startAutomaticSynchronization() async {
        await automaticSyncCoordinator.start { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleAutomaticSyncEvent(event)
            }
        }
        if let syncStatus {
            await automaticSyncCoordinator.scheduleUpload(pendingChangeCount: syncStatus.pendingChangeCount)
        }
    }

    func stopAutomaticSynchronization() async {
        await automaticSyncCoordinator.stop()
    }

    func scheduleAutomaticSynchronization(for status: ZoteroSyncStatusSnapshot) {
        Task {
            await automaticSyncCoordinator.scheduleUpload(pendingChangeCount: status.pendingChangeCount)
        }
    }

    // MARK: Private

    private func handleAutomaticSyncEvent(_ event: ForegroundSyncEvent) {
        switch event {
        case .listening:
            break

        case let .pulled(changeCount, _):
            if changeCount > 0 {
                statusMessage = "Downloaded \(changeCount) remote changes"
            }

        case let .synchronized(changeCount, _, failureCount):
            if failureCount > 0 {
                statusMessage = "Automatic sync completed with \(failureCount) unresolved failures"
            } else if changeCount > 0 {
                statusMessage = "Automatically synchronized \(changeCount) changes"
            }

        case let .failed(message):
            statusMessage = "Automatic sync will retry: \(message)"
        }
    }
}
