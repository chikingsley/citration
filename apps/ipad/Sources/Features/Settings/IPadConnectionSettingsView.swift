import CitrationCore
import SwiftUI

struct IPadConnectionSettingsView: View {
    // MARK: Internal

    @Bindable var model: IPadLibraryModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Zotero Self-Host") {
                    switch model.configuration {
                    case .localOnly:
                        TextField("Server URL", text: $serverURLText)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                        SecureField("Scoped device key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Connect") {
                            Task {
                                if await model.connect(serverURLText: serverURLText, apiKey: apiKey) {
                                    apiKey = ""
                                    dismiss()
                                }
                            }
                        }
                        .disabled(model.isWorking || serverURLText.isEmpty || apiKey.isEmpty)

                    case let .connected(profile):
                        LabeledContent("Server", value: profile.serverURL.host() ?? profile.serverURL.absoluteString)
                        LabeledContent("Library", value: profile.displayName)
                        LabeledContent("Write Access", value: profile.canWrite ? "Yes" : "No")
                        LabeledContent("File Access", value: profile.canAccessFiles ? "Yes" : "No")
                        Button("Disconnect", role: .destructive) {
                            Task {
                                await model.disconnect()
                                dismiss()
                            }
                        }
                    }
                }
                Section {
                    Text(
                        "The scoped device key is stored in the app sandbox with owner-only file permissions. "
                            + "Citration does not create a separate account."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var serverURLText = "https://"
    @State private var apiKey = ""
}
