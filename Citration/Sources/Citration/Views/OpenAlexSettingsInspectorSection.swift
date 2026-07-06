import SwiftUI

struct OpenAlexSettingsInspectorSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("OpenAlex") {
            LabeledContent("Status", value: model.hasOpenAlexAPIKey ? "Configured" : "Not configured")

            SecureField("API key", text: $model.openAlexAPIKeyDraft)
                .textContentType(.password)

            HStack {
                Button(model.isSavingOpenAlexAPIKey ? "Saving..." : "Save Key", systemImage: "key") {
                    model.saveOpenAlexAPIKey()
                }
                .disabled(model.isSavingOpenAlexAPIKey || model.openAlexAPIKeyDraft.bcTrimmedNonEmpty == nil)

                Button("Clear", systemImage: "xmark.circle") {
                    model.clearOpenAlexAPIKey()
                }
                .disabled(model.isSavingOpenAlexAPIKey || !model.hasOpenAlexAPIKey)
            }
        }
        .task {
            await model.refreshOpenAlexAPIKeyStatus()
        }
    }
}
