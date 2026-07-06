import Foundation

extension AppModel {
    func refreshOpenAlexAPIKeyStatus() async {
        hasOpenAlexAPIKey = await configuredOpenAlexAPIKey() != nil
    }

    func saveOpenAlexAPIKey() {
        let key = openAlexAPIKeyDraft.bcTrimmedNonEmpty
        guard key != nil else {
            statusMessage = "Enter an OpenAlex API key"
            return
        }

        isSavingOpenAlexAPIKey = true
        Task {
            await openAlexAPIKeyStore.saveAPIKey(key)
            openAlexAPIKeyDraft = ""
            hasOpenAlexAPIKey = true
            isSavingOpenAlexAPIKey = false
            statusMessage = "Saved OpenAlex key"
            await refreshSelectedItemDiscoverySuggestions()
        }
    }

    func clearOpenAlexAPIKey() {
        isSavingOpenAlexAPIKey = true
        Task {
            await openAlexAPIKeyStore.saveAPIKey(nil)
            openAlexAPIKeyDraft = ""
            hasOpenAlexAPIKey = await environmentOpenAlexAPIKey() != nil
            isSavingOpenAlexAPIKey = false
            statusMessage = "Cleared OpenAlex key"
            await refreshSelectedItemDiscoverySuggestions()
        }
    }

    private func configuredOpenAlexAPIKey() async -> String? {
        if let keychainKey = await openAlexAPIKeyStore.loadAPIKey() {
            return keychainKey
        }
        return await environmentOpenAlexAPIKey()
    }

    private func environmentOpenAlexAPIKey() async -> String? {
        ProcessInfo.processInfo.environment["OPENALEX_API_KEY"]?.bcTrimmedNonEmpty
    }
}
