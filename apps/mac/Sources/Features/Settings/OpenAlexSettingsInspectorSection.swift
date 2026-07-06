import SwiftUI

struct OpenAlexSettingsInspectorSection: View {
    @Bindable var settings: OpenAlexSettingsModel

    var body: some View {
        Section("OpenAlex") {
            LabeledContent("Status", value: settings.hasKey ? "Configured" : "Not configured")

            SecureField("API key", text: $settings.keyDraft)
                .textContentType(.password)

            HStack {
                Button(settings.isSaving ? "Saving..." : "Save Key", systemImage: "key") {
                    settings.saveKey()
                }
                .disabled(settings.isSaving || settings.keyDraft.bcTrimmedNonEmpty == nil)

                Button("Clear", systemImage: "xmark.circle") {
                    settings.clearKey()
                }
                .disabled(settings.isSaving || !settings.hasKey)
            }
        }
        .task {
            await settings.refreshKeyStatus()
        }
    }
}
