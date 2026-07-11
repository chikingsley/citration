import SwiftUI

struct OCRSettingsSection: View {
    @Bindable var settings: OCRSettingsModel

    var body: some View {
        Section("Mistral OCR") {
            LabeledContent("Status", value: settings.hasKey ? "Configured" : "Not configured")

            SecureField("API key", text: $settings.keyDraft)
                .textContentType(.password)

            Text("Used only when an imported PDF has no readable text layer. Results are cached by document hash.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
