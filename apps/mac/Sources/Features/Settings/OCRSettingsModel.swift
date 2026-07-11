import CitrationCore
import Foundation
import Observation

@MainActor
@Observable
final class OCRSettingsModel {
    // MARK: Lifecycle

    init(keyStore: any APIKeyStore) {
        self.keyStore = keyStore
    }

    // MARK: Internal

    var keyDraft = ""
    var hasKey = false
    var isSaving = false

    func bind(context: any LibraryContext) {
        self.context = context
    }

    func refreshKeyStatus() async {
        hasKey = await configuredKey() != nil
    }

    func saveKey() {
        guard let key = keyDraft.bcTrimmedNonEmpty else {
            context?.statusMessage = "Enter a Mistral API key"
            return
        }

        isSaving = true
        Task {
            await keyStore.saveAPIKey(key)
            keyDraft = ""
            hasKey = true
            isSaving = false
            context?.statusMessage = "Saved Mistral OCR key"
        }
    }

    func clearKey() {
        isSaving = true
        Task {
            await keyStore.saveAPIKey(nil)
            keyDraft = ""
            hasKey = environmentKey() != nil
            isSaving = false
            context?.statusMessage = "Cleared Mistral OCR key"
        }
    }

    // MARK: Private

    @ObservationIgnored private let keyStore: any APIKeyStore
    @ObservationIgnored private weak var context: (any LibraryContext)?

    private func configuredKey() async -> String? {
        if let storedKey = await keyStore.loadAPIKey() {
            return storedKey
        }
        return environmentKey()
    }

    private func environmentKey() -> String? {
        ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]?.bcTrimmedNonEmpty
    }
}
