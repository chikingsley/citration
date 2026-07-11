import Foundation

// MARK: - LegacyLibraryMigrator

public struct LegacyLibraryMigrator: Sendable {
    // MARK: Lifecycle

    public init(
        database: CitrationDatabase,
        sources: LegacyLibrarySources,
        backupDirectory: URL
    ) {
        self.database = database
        self.sources = sources
        self.backupDirectory = backupDirectory
    }

    // MARK: Public

    public static let migrationName = "legacy-citration-library-v1"

    public func migrateSynchronously() throws -> LegacyLibraryMigrationReport {
        let result = LegacyMigrationResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await result.store(.success(migrate()))
            } catch {
                result.store(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.load().get()
    }

    public func migrate() async throws -> LegacyLibraryMigrationReport {
        let fingerprint = try sources.fingerprint()
        let backupURL = try sources.backup(to: backupDirectory)
        if
            let completed = try database.completedLegacyMigrationReport(
                name: Self.migrationName,
                fingerprint: fingerprint
            )
        {
            return completed
        }

        let libraryID = try database.upsertLibrary(
            identity: ZoteroLibraryIdentity(type: "local", remoteID: 0),
            name: "Local Library"
        )
        try database.beginLegacyMigration(
            name: Self.migrationName,
            fingerprint: fingerprint,
            backupURL: backupURL
        )

        do {
            let snapshot = try await sources.load()
            let projection = try LegacyZoteroConversion.project(snapshot)
            try database.resetLegacyImport(libraryID: libraryID)
            try database.storeLocalCollections(projection.collections, libraryID: libraryID)
            try database.storeLocalItems(projection.items, libraryID: libraryID)
            try database.ensureAppIdentities(
                collections: projection.collections,
                items: projection.items,
                libraryID: libraryID
            )
            try database.storeLegacySupportState(
                records: projection.records,
                relationships: projection.relationships,
                readerProgress: projection.readerProgress,
                attachmentPaths: projection.attachmentPaths,
                libraryID: libraryID
            )

            let report = LegacyLibraryMigrationReport(
                sourceFingerprint: fingerprint,
                backupURL: backupURL,
                itemCount: snapshot.items.count,
                collectionCount: snapshot.collections.collections.count,
                membershipCount: snapshot.collections.memberships.count,
                noteCount: snapshot.notes.count,
                attachmentCount: projection.records.count { $0.entityKind == "attachment" },
                annotationCount: snapshot.annotations.count,
                relationshipCount: snapshot.relationships.count,
                readerProgressCount: snapshot.readerProgress.count
            )
            try verify(report: report, projection: projection, libraryID: libraryID)
            try database.completeLegacyMigration(name: Self.migrationName, report: report)
            return report
        } catch {
            try? database.failLegacyMigration(name: Self.migrationName, error: error)
            throw error
        }
    }

    // MARK: Private

    private let database: CitrationDatabase
    private let sources: LegacyLibrarySources
    private let backupDirectory: URL

    private func verify(
        report: LegacyLibraryMigrationReport,
        projection: LegacyMigrationProjection,
        libraryID: Int64
    ) throws {
        let expected = LegacyMigrationInspection(
            status: "running",
            legacyRecordCount: projection.records.count,
            relationshipCount: report.relationshipCount,
            readerStateCount: report.readerProgressCount,
            downloadedAttachmentCount: projection.attachmentPaths.count
        )
        let actual = try database.inspectLegacyMigration(name: Self.migrationName, libraryID: libraryID)
        guard expected == actual else {
            throw LegacyLibraryMigrationError.verificationFailed(expected: expected, actual: actual)
        }
        guard try database.objectCount(libraryID: libraryID, kind: .collection) == report.collectionCount else {
            throw LegacyLibraryMigrationError.verificationFailed(expected: expected, actual: actual)
        }
        guard try database.objectCount(libraryID: libraryID, kind: .item) == report.zoteroItemObjectCount else {
            throw LegacyLibraryMigrationError.verificationFailed(expected: expected, actual: actual)
        }
        guard try database.integrityCheck() == "ok" else {
            throw LegacyLibraryMigrationError.verificationFailed(expected: expected, actual: actual)
        }
    }
}

// MARK: - LegacyMigrationResultBox

private final class LegacyMigrationResultBox: @unchecked Sendable {
    // MARK: Internal

    func store(_ value: Result<LegacyLibraryMigrationReport, any Error>) {
        lock.lock()
        result = value
        lock.unlock()
    }

    func load() -> Result<LegacyLibraryMigrationReport, any Error> {
        lock.lock()
        defer { lock.unlock() }
        return result ?? .failure(CancellationError())
    }

    // MARK: Private

    private let lock: NSLock = .init()
    private var result: Result<LegacyLibraryMigrationReport, any Error>?
}
