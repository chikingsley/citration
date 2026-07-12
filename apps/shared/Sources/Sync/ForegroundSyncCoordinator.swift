import CitrationCore
import Foundation

// MARK: - ForegroundSyncEvent

enum ForegroundSyncEvent: Sendable {
    case listening
    case pulled(changeCount: Int, version: Int64)
    case synchronized(changeCount: Int, version: Int64, failureCount: Int)
    case failed(String)
}

// MARK: - ForegroundSyncCoordinator

/// Owns the one foreground streaming subscription and coalesces local writes
/// before asking the production Zotero sync engine to upload them.
actor ForegroundSyncCoordinator {
    // MARK: Lifecycle

    init(connectionManager: ZoteroConnectionManager) {
        self.connectionManager = connectionManager
    }

    // MARK: Internal

    func start(eventHandler: @escaping @Sendable (ForegroundSyncEvent) -> Void) async {
        stop()
        self.eventHandler = eventHandler
        guard case let .connected(profile) = try? await connectionManager.configuration() else {
            return
        }
        connectedProfile = profile

        do {
            let subscription = try await connectionManager.streamingSubscription()
            streamingSubscription = subscription
            eventHandler(.listening)
            streamingTask = Task { [weak self] in
                do {
                    for try await report in subscription.reports {
                        guard !Task.isCancelled else {
                            return
                        }
                        let changeCount = report.itemCount + report.collectionCount + report.searchCount
                        await self?.emit(.pulled(changeCount: changeCount, version: report.currentVersion))
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await self?.emit(.failed(error.localizedDescription))
                }
            }
        } catch {
            eventHandler(.failed(error.localizedDescription))
        }
    }

    func stop() {
        scheduledUploadTask?.cancel()
        scheduledUploadTask = nil
        streamingTask?.cancel()
        streamingTask = nil
        streamingSubscription?.cancel()
        streamingSubscription = nil
        connectedProfile = nil
        eventHandler = nil
        synchronizeAgain = false
    }

    func scheduleUpload(pendingChangeCount: Int) {
        scheduledUploadTask?.cancel()
        scheduledUploadTask = nil
        guard pendingChangeCount > 0, connectedProfile?.canWrite == true else {
            return
        }
        scheduledUploadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else {
                    return
                }
                await self?.runSynchronization()
            } catch {
                return
            }
        }
    }

    // MARK: Private

    private let connectionManager: ZoteroConnectionManager
    private var connectedProfile: ZoteroConnectionProfile?
    private var streamingSubscription: ZoteroStreamingSubscription?
    private var streamingTask: Task<Void, Never>?
    private var scheduledUploadTask: Task<Void, Never>?
    private var eventHandler: (@Sendable (ForegroundSyncEvent) -> Void)?
    private var isSynchronizing = false
    private var synchronizeAgain = false

    private func emit(_ event: ForegroundSyncEvent) {
        eventHandler?(event)
    }

    private func runSynchronization() async {
        guard connectedProfile?.canWrite == true else {
            return
        }
        guard !isSynchronizing else {
            synchronizeAgain = true
            return
        }

        isSynchronizing = true
        repeat {
            synchronizeAgain = false
            do {
                if let report = try await connectionManager.synchronize() {
                    let metadata = report.metadata
                    let changeCount = metadata.uploadedObjectCount
                        + metadata.deletedObjectCount
                        + metadata.pulledObjectCount
                    emit(.synchronized(
                        changeCount: changeCount,
                        version: metadata.currentVersion,
                        failureCount: metadata.unresolvedFailureCount
                    ))
                }
            } catch {
                emit(.failed(error.localizedDescription))
            }
        } while synchronizeAgain && !Task.isCancelled
        isSynchronizing = false
    }
}
