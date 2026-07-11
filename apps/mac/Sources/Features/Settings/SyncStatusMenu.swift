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
        ForEach(status.failures.prefix(5)) { failure in
            Text("\(failure.operation): \(failure.message)")
        }
        if status.failures.count > 5 {
            Text("\(status.failures.count - 5) more failures")
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
}
