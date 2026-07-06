import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class OpenAlexSettingsModel {
    // MARK: Lifecycle

    init(keyStore: any APIKeyStore) {
        self.keyStore = keyStore
    }

    // MARK: Internal

    var keyDraft: String = ""
    var hasKey: Bool = false
    var isSaving: Bool = false

    let keyStore: any APIKeyStore

    func bind(context: any LibraryContext, insights: InsightsModel) {
        self.context = context
        self.insights = insights
    }

    func refreshKeyStatus() async {
        hasKey = await configuredKey() != nil
    }

    func saveKey() {
        let key = keyDraft.bcTrimmedNonEmpty
        guard key != nil else {
            context?.statusMessage = "Enter an OpenAlex API key"
            return
        }

        isSaving = true
        Task {
            await keyStore.saveAPIKey(key)
            keyDraft = ""
            hasKey = true
            isSaving = false
            context?.statusMessage = "Saved OpenAlex key"
            await insights?.refreshForSelection()
        }
    }

    func clearKey() {
        isSaving = true
        Task {
            await keyStore.saveAPIKey(nil)
            keyDraft = ""
            hasKey = environmentKey() != nil
            isSaving = false
            context?.statusMessage = "Cleared OpenAlex key"
            await insights?.refreshForSelection()
        }
    }

    // MARK: Private

    @ObservationIgnored private weak var context: (any LibraryContext)?

    @ObservationIgnored private weak var insights: InsightsModel?

    private func configuredKey() async -> String? {
        if let storedKey = await keyStore.loadAPIKey() {
            return storedKey
        }
        return environmentKey()
    }

    private func environmentKey() -> String? {
        ProcessInfo.processInfo.environment["OPENALEX_API_KEY"]?.bcTrimmedNonEmpty
    }
}
