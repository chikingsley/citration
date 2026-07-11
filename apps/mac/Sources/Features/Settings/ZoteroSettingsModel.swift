import CitrationCore
import Foundation
import Observation

// MARK: - ZoteroSettingsContext

@MainActor
protocol ZoteroSettingsContext: AnyObject {
    var statusMessage: String { get set }

    func activateLibrary(_ profile: ZoteroConnectionProfile) async throws
    func activateLocalLibrary() async throws
    func refreshLibrary() async
}

// MARK: - AppModel + ZoteroSettingsContext

extension AppModel: ZoteroSettingsContext {}

// MARK: - ZoteroSettingsModel

@MainActor
@Observable
final class ZoteroSettingsModel {
    // MARK: Lifecycle

    init(connectionManager: ZoteroConnectionManager) {
        self.connectionManager = connectionManager
    }

    // MARK: Internal

    enum Operation: Equatable {
        case connecting
        case disconnecting
        case synchronizing
    }

    var serverURLDraft = ""
    var apiKeyDraft = ""
    var profile: ZoteroConnectionProfile?
    var operation: Operation?
    var errorMessage: String?
    var resultMessage: String?

    var isConnected: Bool {
        profile != nil
    }

    var isWorking: Bool {
        operation != nil
    }

    func bind(context: any ZoteroSettingsContext) {
        self.context = context
    }

    func refresh() async {
        do {
            switch try await connectionManager.configuration() {
            case .localOnly:
                profile = nil
            case let .connected(profile):
                self.profile = profile
                serverURLDraft = profile.serverURL.absoluteString
            }
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    func connect() async {
        guard !isWorking else {
            return
        }
        guard let serverURL = URL(string: serverURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = ZoteroTransportError.invalidServerURL.localizedDescription
            return
        }

        operation = .connecting
        errorMessage = nil
        resultMessage = nil
        do {
            let profile = try await connectionManager.connect(serverURL: serverURL, apiKey: apiKeyDraft)
            try await context?.activateLibrary(profile)
            self.profile = profile
            serverURLDraft = profile.serverURL.absoluteString
            apiKeyDraft = ""
            resultMessage = "Connected and synchronized \(profile.displayName)."
            context?.statusMessage = "Connected to \(profile.displayName)"
        } catch {
            errorMessage = message(for: error)
            context?.statusMessage = "Connection failed"
        }
        operation = nil
    }

    func synchronize() async {
        guard !isWorking, let profile else {
            return
        }
        operation = .synchronizing
        errorMessage = nil
        resultMessage = nil
        do {
            if profile.canWrite {
                let report = try await connectionManager.synchronize()
                try await context?.activateLibrary(profile)
                resultMessage = report.map(Self.summary) ?? "Nothing to synchronize."
            } else {
                let report = try await connectionManager.pullReadOnly()
                try await context?.activateLibrary(profile)
                resultMessage = report.map(Self.summary) ?? "Nothing to synchronize."
            }
            context?.statusMessage = "Synchronization complete"
        } catch {
            errorMessage = message(for: error)
            context?.statusMessage = "Synchronization failed"
        }
        operation = nil
    }

    func useLocalLibrary() async {
        guard !isWorking else {
            return
        }
        operation = .disconnecting
        errorMessage = nil
        resultMessage = nil
        do {
            try await connectionManager.useLocalOnly()
            try await context?.activateLocalLibrary()
            profile = nil
            apiKeyDraft = ""
            resultMessage = "Using the local library. Cached remote data remains in Citration's database."
            context?.statusMessage = "Using local library"
        } catch {
            errorMessage = message(for: error)
            context?.statusMessage = "Could not switch libraries"
        }
        operation = nil
    }

    // MARK: Private

    @ObservationIgnored private let connectionManager: ZoteroConnectionManager
    @ObservationIgnored private weak var context: (any ZoteroSettingsContext)?

    private static func summary(_ report: ZoteroClientSynchronizationReport) -> String {
        let metadata = report.metadata
        let changed = metadata.uploadedObjectCount + metadata.deletedObjectCount + metadata.pulledObjectCount
        if changed == 0, metadata.unresolvedFailureCount == 0 {
            return "Library is up to date at version \(metadata.currentVersion)."
        }
        return "Synchronized \(changed) object changes at version \(metadata.currentVersion); "
            + "\(metadata.unresolvedFailureCount) unresolved failures."
    }

    private static func summary(_ report: ZoteroPullReport) -> String {
        let changed = report.itemCount + report.collectionCount + report.searchCount
        return "Downloaded \(changed) object changes at version \(report.currentVersion)."
    }

    private func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
