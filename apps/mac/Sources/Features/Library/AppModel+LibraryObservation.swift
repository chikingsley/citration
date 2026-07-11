import CitrationCore
import Foundation

extension AppModel {
    func activateLibrary(_ profile: ZoteroConnectionProfile) async throws {
        guard let store = store as? CitrationLibraryStore else {
            throw AppLibrarySelectionError.productionStoreUnavailable
        }
        let libraryID = try await store.selectLibrary(
            identity: profile.libraryIdentity,
            name: profile.displayName
        )
        switchObservations(to: libraryID)
        await refreshConnectedFeatures()
    }

    func activateLocalLibrary() async throws {
        guard let store = store as? CitrationLibraryStore else {
            throw AppLibrarySelectionError.productionStoreUnavailable
        }
        let libraryID = try await store.selectLibrary(
            identity: .init(type: "local", remoteID: 0),
            name: "Local Library"
        )
        switchObservations(to: libraryID)
        await refreshConnectedFeatures()
    }

    func startLibraryObservation() {
        guard let observedLibraryID else {
            return
        }
        libraryObservation = database.observeLibraryItems(
            libraryID: observedLibraryID,
            onError: { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Failed to observe library changes"
                }
            },
            onChange: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    libraryObservationRevision += 1
                    await collections.refresh()
                    await refreshItems()
                }
            }
        )
    }

    func startNavigationObservation() {
        guard let observedLibraryID else {
            return
        }
        navigationObservation = database.observeLibraryNavigation(
            libraryID: observedLibraryID,
            onError: { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Failed to observe library navigation"
                }
            },
            onChange: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    savedSearches = snapshot.savedSearches
                    deletedItemCount = snapshot.deletedItemCount
                    navigationObservationRevision += 1
                }
            }
        )
    }

    // MARK: Private

    private func switchObservations(to libraryID: Int64) {
        libraryObservation?.cancel()
        navigationObservation?.cancel()
        libraryObservation = nil
        navigationObservation = nil
        observedLibraryID = libraryID
        startLibraryObservation()
        startNavigationObservation()
    }

    private func refreshConnectedFeatures() async {
        await collections.refresh()
        await refreshItems()
        await relationships.refresh()
        await notes.refreshForSelection()
    }
}

// MARK: - AppLibrarySelectionError

private enum AppLibrarySelectionError: Error {
    case productionStoreUnavailable
}
