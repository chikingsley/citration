import CitrationCore
import SwiftUI

struct SyncStatusMenu: View {
    // MARK: Internal

    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Text(model.statusMessage)
            Divider()
            if let profile = model.zoteroSettings.profile {
                Text(profile.displayName)
                if let status = model.syncStatus {
                    Text("Library version \(status.currentVersion)")
                    statusRows(status)
                }
                Divider()
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                    Task {
                        await model.zoteroSettings.synchronize()
                    }
                }
                .disabled(model.zoteroSettings.isWorking)
                if let status = model.syncStatus, !status.failures.isEmpty {
                    Button("Retry All Failures", systemImage: "arrow.clockwise") {
                        model.retryAllSyncFailures()
                    }
                    .disabled(!model.syncRecoveryOperationIDs.isEmpty)
                }
            } else {
                Text("Local library")
                Text("Connect a Zotero-compatible server in Settings.")
                Divider()
                SettingsLink {
                    Label("Open Settings", systemImage: "gear")
                }
            }
        } label: {
            statusLabel
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .help(helpText)
    }

    // MARK: Private

    private var helpText: String {
        if let status = model.syncStatus, !status.failures.isEmpty {
            return "Synchronization needs attention"
        }
        return model.zoteroSettings.isConnected ? "Synchronization status" : "Local library"
    }

    @ViewBuilder
    private var statusLabel: some View {
        if model.zoteroSettings.operation == .synchronizing {
            Label("Synchronizing", systemImage: "arrow.triangle.2.circlepath")
        } else if let status = model.syncStatus, !status.failures.isEmpty {
            Label("\(status.failures.count) sync failures", systemImage: "exclamationmark.triangle.fill")
        } else if let status = model.syncStatus, status.pendingChangeCount > 0 {
            Label("\(status.pendingChangeCount) pending changes", systemImage: "arrow.up.arrow.down")
        } else if model.zoteroSettings.isConnected {
            Label("Synchronized", systemImage: "checkmark.icloud")
        } else {
            Label("Local library", systemImage: "externaldrive")
        }
    }

    @ViewBuilder
    private func statusRows(_ status: ZoteroSyncStatusSnapshot) -> some View {
        if status.pendingChangeCount > 0 {
            Label("\(status.pendingChangeCount) pending object changes", systemImage: "arrow.up.arrow.down")
        }
        if status.downloadingAttachmentCount > 0 {
            Label("\(status.downloadingAttachmentCount) attachment downloads", systemImage: "arrow.down.circle")
        }
        if status.staleAttachmentCount > 0 {
            Label("\(status.staleAttachmentCount) stale attachment files", systemImage: "arrow.clockwise.circle")
        }
        if status.failedAttachmentCount > 0 {
            Label("\(status.failedAttachmentCount) failed attachment transfers", systemImage: "exclamationmark.icloud")
        }
        ForEach(status.failures) { failure in
            failureMenu(failure)
        }
        if
            status.pendingChangeCount == 0,
            status.downloadingAttachmentCount == 0,
            status.staleAttachmentCount == 0,
            status.failedAttachmentCount == 0,
            status.failures.isEmpty
        {
            Label("Up to date", systemImage: "checkmark.circle")
        }
    }

    private func failureMenu(_ failure: ZoteroSyncFailureSummary) -> some View {
        Menu {
            Text("\(failure.objectKind.rawValue):\(failure.objectKey)")
            Text(failure.message)
            if failure.retryCount > 0 {
                Text("Attempts: \(failure.retryCount)")
            }
            if let nextRetryAt = failure.nextRetryAt {
                Text("Next retry: \(nextRetryAt.formatted(date: .omitted, time: .shortened))")
            }
            Divider()
            Button("Retry Now", systemImage: "arrow.clockwise") {
                model.retrySyncFailure(failure)
            }
            if failure.operation == "merge-conflict" {
                Divider()
                Button("Keep Local Version") {
                    model.resolveSyncConflict(failure, resolution: .keepLocal)
                }
                Button("Keep Remote Version") {
                    model.resolveSyncConflict(failure, resolution: .keepRemote)
                }
                Button("Delete Object", role: .destructive) {
                    model.resolveSyncConflict(failure, resolution: .delete)
                }
            }
        } label: {
            Label("\(failure.operation): \(failure.message)", systemImage: "exclamationmark.triangle")
        }
        .disabled(model.syncRecoveryOperationIDs.contains(failure.id))
    }
}
