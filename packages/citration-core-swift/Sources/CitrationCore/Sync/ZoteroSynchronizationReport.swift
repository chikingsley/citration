import Foundation

// MARK: - ZoteroSynchronizationReport

public struct ZoteroSynchronizationReport: Equatable, Sendable {
    public let userID: Int64
    public let uploadedObjectCount: Int
    public let unchangedObjectCount: Int
    public let deletedObjectCount: Int
    public let pulledObjectCount: Int
    public let currentVersion: Int64
    public let unresolvedFailureCount: Int
}

// MARK: - ZoteroWritePass

private struct ZoteroWritePass {
    var uploaded = 0
    var unchanged = 0
    var deleted = 0
}

public extension ZoteroSyncEngine {
    func synchronize(maxPreconditionAttempts: Int = 3) async throws -> ZoteroSynchronizationReport {
        let keyInfo = try await client.keyInfo()
        guard keyInfo.canWriteUserLibrary else {
            throw ZoteroTransportError.keyCannotWriteLibrary
        }
        let identity = ZoteroLibraryIdentity(type: "user", remoteID: keyInfo.userID)
        let libraryID = try database.upsertLibrary(identity: identity, name: keyInfo.displayName)
        var pulledObjects = 0

        for attempt in 0 ..< maxPreconditionAttempts {
            do {
                var writes = try await uploadPending(userID: keyInfo.userID, identity: identity, libraryID: libraryID)
                let pull = try await pullReadOnly()
                pulledObjects += pull.itemCount + pull.collectionCount + pull.searchCount
                let mergedWrites = try await uploadPending(
                    userID: keyInfo.userID,
                    identity: identity,
                    libraryID: libraryID
                )
                writes.uploaded += mergedWrites.uploaded
                writes.unchanged += mergedWrites.unchanged
                writes.deleted += mergedWrites.deleted
                return try ZoteroSynchronizationReport(
                    userID: keyInfo.userID,
                    uploadedObjectCount: writes.uploaded,
                    unchangedObjectCount: writes.unchanged,
                    deletedObjectCount: writes.deleted,
                    pulledObjectCount: pulledObjects,
                    currentVersion: database.libraryVersion(identity: identity),
                    unresolvedFailureCount: database.unresolvedSyncFailureCount(libraryID: libraryID)
                )
            } catch let error as ZoteroTransportError {
                guard case .preconditionFailed = error, attempt + 1 < maxPreconditionAttempts else {
                    throw error
                }
                let pull = try await pullReadOnly()
                pulledObjects += pull.itemCount + pull.collectionCount + pull.searchCount
            }
        }
        throw ZoteroSyncError.remoteLibraryKeptChanging(attempts: maxPreconditionAttempts)
    }

    private func uploadPending(
        userID: Int64,
        identity: ZoteroLibraryIdentity,
        libraryID: Int64
    ) async throws -> ZoteroWritePass {
        var pass = ZoteroWritePass()
        var version = try database.libraryVersion(identity: identity)
        for kind in [ZoteroObjectKind.collection, .item] {
            let pending = try database.pendingUploads(kind: kind, libraryID: libraryID, limit: 100_000)
            for batch in orderedForUpload(pending, kind: kind).chunked(maxCount: 50) {
                let result = try await writeBatch(
                    batch,
                    kind: kind,
                    userID: userID,
                    version: version,
                    libraryID: libraryID
                )
                version = result.version
                pass.uploaded += result.report.successful.count
                pass.unchanged += result.report.unchanged.count
            }
        }
        for kind in [ZoteroObjectKind.item, .collection] {
            while true {
                let keys = try database.pendingDeletions(kind: kind, libraryID: libraryID)
                guard !keys.isEmpty else {
                    break
                }
                version = try await deleteBatch(
                    keys,
                    kind: kind,
                    userID: userID,
                    version: version,
                    libraryID: libraryID
                )
                pass.deleted += keys.count
            }
        }
        return pass
    }

    private func writeBatch(
        _ batch: [ZoteroStoredObject],
        kind: ZoteroObjectKind,
        userID: Int64,
        version: Int64,
        libraryID: Int64
    ) async throws -> (report: ZoteroWriteReport, version: Int64) {
        do {
            let response = try await client.writeObjects(
                path: endpoint(userID: userID, kind: kind),
                objects: batch,
                libraryVersion: version
            )
            guard let nextVersion = response.libraryVersion else {
                throw ZoteroTransportError.missingHeader("Last-Modified-Version")
            }
            try database.applyWriteReport(
                response.value,
                batch: batch,
                kind: kind,
                libraryVersion: nextVersion,
                libraryID: libraryID
            )
            return (response.value, nextVersion)
        } catch let error as ZoteroTransportError {
            if case .preconditionFailed = error {
                throw error
            }
            try database.recordWriteTransportFailure(
                objects: batch,
                operation: "upload",
                message: String(describing: error),
                libraryID: libraryID
            )
            throw error
        }
    }

    private func deleteBatch(
        _ keys: [String],
        kind: ZoteroObjectKind,
        userID: Int64,
        version: Int64,
        libraryID: Int64
    ) async throws -> Int64 {
        do {
            let nextVersion = try await client.deleteObjects(
                path: endpoint(userID: userID, kind: kind),
                keyParameter: kind == .item ? "itemKey" : "collectionKey",
                keys: keys,
                libraryVersion: version
            )
            try database.markDeletionsUploaded(
                keys: keys,
                kind: kind,
                libraryVersion: nextVersion,
                libraryID: libraryID
            )
            return nextVersion
        } catch let error as ZoteroTransportError {
            if case .preconditionFailed = error {
                throw error
            }
            try database.recordDeletionTransportFailure(
                keys: keys,
                kind: kind,
                message: String(describing: error),
                libraryID: libraryID
            )
            throw error
        }
    }

    private func endpoint(userID: Int64, kind: ZoteroObjectKind) -> String {
        kind == .collection ? "users/\(userID)/collections" : "users/\(userID)/items"
    }

    private func orderedForUpload(
        _ objects: [ZoteroStoredObject],
        kind: ZoteroObjectKind
    ) -> [ZoteroStoredObject] {
        let byKey = Dictionary(uniqueKeysWithValues: objects.map { ($0.key, $0) })
        var visited = Set<String>()
        var visiting = Set<String>()
        var result = [ZoteroStoredObject]()
        func visit(_ object: ZoteroStoredObject) {
            guard !visited.contains(object.key), !visiting.contains(object.key) else {
                return
            }
            visiting.insert(object.key)
            let field = kind == .collection ? "parentCollection" : "parentItem"
            if
                let parent = object.current.objectValue?["data"]?.objectValue?[field]?.stringValue,
                let parentObject = byKey[parent]
            {
                visit(parentObject)
            }
            visiting.remove(object.key)
            visited.insert(object.key)
            result.append(object)
        }
        for object in objects.sorted(by: { $0.key < $1.key }) {
            visit(object)
        }
        return result
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        stride(from: 0, to: count, by: maxCount).map { start in
            Array(self[start ..< Swift.min(start + maxCount, count)])
        }
    }
}
