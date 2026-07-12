import CitrationCore
import Foundation

extension AppModel {
    func selectItem(id: UUID?) {
        selectItem(identity: id.flatMap { appUUID in
            items.first { $0.identity.appUUID == appUUID }?.identity
        })
    }

    func selectItem(identity: SynchronizedLibraryItemIdentity?) {
        guard selectedItemIdentity != identity else {
            if let identity, selectedLibraryItemDetail == nil {
                startSelectionRefresh(identity: identity)
            }
            return
        }

        selectionRefreshTask?.cancel()
        notes.draft = ""
        citation.clearExport()
        relationships.clearSelectionDrafts()
        insights.clearForSelectionChange()
        importer.clearMetadataDiagnostics()
        importer.selectedItemAttachments = []
        selectedAttachmentCacheRecords = []
        notes.selectedItemNotes = []
        relationships.selectedItemRelationships = []
        collections.selectedItemCollectionIDs = []
        libraryReader.clearIfSelectionChanged(to: identity?.appUUID)
        selectedItemIdentity = identity
        selectedLibraryItemDetail = identity.flatMap(cachedItemDetail)

        guard let identity else {
            return
        }
        startSelectionRefresh(identity: identity)
    }

    func refreshSelectionAfterLibraryReload() {
        guard let identity = selectedItemIdentity else {
            return
        }
        startSelectionRefresh(identity: identity, forceDetailRefresh: true)
    }

    func pruneItemDetailCache(validIdentities: Set<SynchronizedLibraryItemIdentity>) {
        itemDetailCache = itemDetailCache.filter { validIdentities.contains($0.key) }
        itemDetailCacheOrder.removeAll { !validIdentities.contains($0) }
    }

    func installItemDetail(_ detail: SynchronizedLibraryItem) {
        cacheItemDetail(detail)
        if selectedItemIdentity == detail.identity {
            selectedLibraryItemDetail = detail
        }
    }

    func hydrateItemDetail(_ summary: SynchronizedLibraryItem) async -> SynchronizedLibraryItem {
        let database = database
        let projected = await Task.detached {
            try? database.fetchProjectedItem(
                libraryID: summary.identity.libraryID,
                key: summary.identity.objectKey
            )
        }.value
        guard let projected else {
            return summary
        }
        return SynchronizedLibraryItem(
            identity: summary.identity,
            bibliographic: summary.bibliographic,
            projected: projected,
            zoteroItemType: summary.zoteroItemType,
            zoteroDate: summary.zoteroDate,
            publicationTitle: summary.publicationTitle,
            parentItemKey: summary.parentItemKey
        )
    }

    // MARK: Private

    private func startSelectionRefresh(
        identity: SynchronizedLibraryItemIdentity,
        forceDetailRefresh: Bool = false
    ) {
        selectionRefreshTask?.cancel()
        selectionRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if forceDetailRefresh || selectedLibraryItemDetail == nil {
                guard
                    !Task.isCancelled,
                    selectedItemIdentity == identity,
                    let summary = items.first(where: { $0.identity == identity })
                else {
                    return
                }
                let detail = await hydrateItemDetail(summary)
                guard !Task.isCancelled, selectedItemIdentity == identity else {
                    return
                }
                cacheItemDetail(detail)
                selectedLibraryItemDetail = detail
            }

            collections.refreshSelectedItemMemberships()
            relationships.refreshForSelection()

            async let citationRefresh: Void = citation.renderPreviewForSelection()
            async let attachmentRefresh: Void = refreshAttachmentsForSelection(identity: identity)
            async let noteRefresh: Void = notes.refreshForSelection()
            async let insightRefresh: Void = insights.refreshForSelection()
            _ = await (citationRefresh, attachmentRefresh, noteRefresh, insightRefresh)
        }
    }

    private func refreshAttachmentsForSelection(identity: SynchronizedLibraryItemIdentity) async {
        await importer.refreshSelectedItemAttachments()
        guard !Task.isCancelled, selectedItemIdentity == identity else {
            return
        }
        refreshSelectedAttachmentCacheRecords()
    }

    private func cachedItemDetail(for identity: SynchronizedLibraryItemIdentity) -> SynchronizedLibraryItem? {
        guard let detail = itemDetailCache[identity] else {
            return nil
        }
        itemDetailCacheOrder.removeAll { $0 == identity }
        itemDetailCacheOrder.append(identity)
        return detail
    }

    private func cacheItemDetail(_ detail: SynchronizedLibraryItem) {
        let identity = detail.identity
        itemDetailCache[identity] = detail
        itemDetailCacheOrder.removeAll { $0 == identity }
        itemDetailCacheOrder.append(identity)
        while itemDetailCacheOrder.count > 128, let evicted = itemDetailCacheOrder.first {
            itemDetailCacheOrder.removeFirst()
            itemDetailCache[evicted] = nil
        }
    }
}
