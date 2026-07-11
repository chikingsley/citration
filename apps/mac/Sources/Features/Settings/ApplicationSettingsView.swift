import CitrationCore
import SwiftUI

// MARK: - ApplicationSettingsView

struct ApplicationSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            ZoteroConnectionSettingsView(settings: model.zoteroSettings)
                .tabItem {
                    Label("Library", systemImage: "arrow.triangle.2.circlepath")
                }

            Form {
                OpenAlexSettingsSection(settings: model.openAlexSettings)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Services", systemImage: "wand.and.stars")
            }
        }
        .frame(width: 560, height: 430)
    }
}

// MARK: - ZoteroConnectionSettingsView

private struct ZoteroConnectionSettingsView: View {
    // MARK: Internal

    @Bindable var settings: ZoteroSettingsModel

    var body: some View {
        Form {
            Section("Zotero Library") {
                if let profile = settings.profile {
                    connectedProfile(profile)
                } else {
                    connectionFields
                }
            }

            if let resultMessage = settings.resultMessage {
                Section("Status") {
                    Label(resultMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = settings.errorMessage {
                Section("Action Required") {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await settings.refresh()
        }
    }

    // MARK: Private

    @ViewBuilder
    private var connectionFields: some View {
        TextField("Server URL", text: $settings.serverURLDraft, prompt: Text("https://zotero.example.com"))
            .textContentType(.URL)
        SecureField("Scoped API or device key", text: $settings.apiKeyDraft)
            .textContentType(.password)

        Text(
            "The key must read the personal library. Write and file permissions enable edits and attachments. "
                + "Citration stores it in a permission-restricted Application Support file, never in the database "
                + "or macOS Keychain."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        HStack {
            Spacer()
            Button(settings.operation == .connecting ? "Connecting…" : "Connect") {
                Task {
                    await settings.connect()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(settings.isWorking || settings.serverURLDraft.isEmpty || settings.apiKeyDraft.isEmpty)
        }
    }

    @ViewBuilder
    private func connectedProfile(_ profile: ZoteroConnectionProfile) -> some View {
        LabeledContent("Library", value: profile.displayName)
        LabeledContent("Server") {
            Text(profile.serverURL.absoluteString)
                .textSelection(.enabled)
        }
        LabeledContent("User", value: profile.username)
        LabeledContent("Library access", value: profile.canWrite ? "Read and write" : "Read only")
        LabeledContent("Attachment files", value: profile.canAccessFiles ? "Enabled" : "Unavailable")

        HStack {
            Button(settings.operation == .synchronizing ? "Synchronizing…" : "Sync Now") {
                Task {
                    await settings.synchronize()
                }
            }
            .disabled(settings.isWorking)

            Spacer()

            Button("Use Local Library", role: .destructive) {
                Task {
                    await settings.useLocalLibrary()
                }
            }
            .disabled(settings.isWorking)
        }
    }
}
