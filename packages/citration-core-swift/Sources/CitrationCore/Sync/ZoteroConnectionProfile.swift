import Foundation

// MARK: - ZoteroConnectionProfile

public struct ZoteroConnectionProfile: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        serverURL: URL,
        userID: Int64,
        username: String,
        displayName: String,
        canWrite: Bool,
        canAccessFiles: Bool
    ) {
        self.serverURL = serverURL
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.canWrite = canWrite
        self.canAccessFiles = canAccessFiles
    }

    // MARK: Public

    public let serverURL: URL
    public let userID: Int64
    public let username: String
    public let displayName: String
    public let canWrite: Bool
    public let canAccessFiles: Bool

    public var libraryIdentity: ZoteroLibraryIdentity {
        ZoteroLibraryIdentity(type: "user", remoteID: userID)
    }
}

// MARK: - ZoteroConnectionConfiguration

public enum ZoteroConnectionConfiguration: Equatable, Sendable {
    case localOnly
    case connected(ZoteroConnectionProfile)
}

// MARK: - ZoteroConnectionManagerError

public enum ZoteroConnectionManagerError: Error, Equatable, Sendable {
    case attachmentStorageUnavailable
    case missingCredential
}

// MARK: - ZoteroClientSynchronizationReport

public struct ZoteroClientSynchronizationReport: Equatable, Sendable {
    public let metadata: ZoteroSynchronizationReport
    public let attachments: ZoteroAttachmentUploadReport?
}

// MARK: - ZoteroConnectionManager

public actor ZoteroConnectionManager {
    // MARK: Lifecycle

    public init(
        database: CitrationDatabase,
        credentialStore: any ZoteroCredentialStore,
        attachmentsDirectory: URL? = nil,
        session: URLSession = .shared
    ) {
        self.database = database
        self.credentialStore = credentialStore
        self.attachmentsDirectory = attachmentsDirectory
        self.session = session
    }

    // MARK: Public

    public func configuration() throws -> ZoteroConnectionConfiguration {
        try database.loadZoteroConnectionProfile().map(ZoteroConnectionConfiguration.connected) ?? .localOnly
    }

    public func connect(serverURL: URL, apiKey: String) async throws -> ZoteroConnectionProfile {
        let connection = try ZoteroConnection(serverURL: serverURL, apiKey: apiKey)
        let client = ZoteroAPIClient(connection: connection, session: session)
        let keyInfo = try await client.keyInfo()
        let profile = ZoteroConnectionProfile(
            serverURL: connection.serverURL,
            userID: keyInfo.userID,
            username: keyInfo.username,
            displayName: keyInfo.displayName,
            canWrite: keyInfo.canWriteUserLibrary,
            canAccessFiles: keyInfo.canAccessUserFiles
        )
        let engine = ZoteroSyncEngine(database: database, client: client)
        _ = try await engine.pullReadOnly()
        _ = try database.promoteLocalLibrary(to: profile.libraryIdentity, targetName: profile.displayName)
        if profile.canWrite {
            _ = try await engine.synchronize()
            if profile.canAccessFiles, let attachmentsDirectory {
                let report = try await ZoteroAttachmentTransfer(
                    database: database,
                    client: client,
                    attachmentsDirectory: attachmentsDirectory
                ).uploadPending()
                if report.uploadedCount + report.alreadyCurrentCount > 0 {
                    _ = try await engine.pullReadOnly()
                }
            }
        }
        let previousCredential = try await credentialStore.loadCredential()
        try await credentialStore.saveCredential(connection.apiKey)
        do {
            try database.saveZoteroConnectionProfile(profile)
        } catch {
            try? await credentialStore.saveCredential(previousCredential)
            throw error
        }
        return profile
    }

    public func useLocalOnly() async throws {
        let previousCredential = try await credentialStore.loadCredential()
        try await credentialStore.saveCredential(nil)
        do {
            try database.clearZoteroConnectionProfile()
        } catch {
            try? await credentialStore.saveCredential(previousCredential)
            throw error
        }
    }

    public func activeConnection() async throws -> ZoteroConnection? {
        guard let profile = try database.loadZoteroConnectionProfile() else {
            return nil
        }
        guard let apiKey = try await credentialStore.loadCredential() else {
            throw ZoteroConnectionManagerError.missingCredential
        }
        return try ZoteroConnection(serverURL: profile.serverURL, apiKey: apiKey)
    }

    public func pullReadOnly() async throws -> ZoteroPullReport? {
        guard let connection = try await activeConnection() else {
            return nil
        }
        return try await ZoteroSyncEngine(
            database: database,
            client: ZoteroAPIClient(connection: connection, session: session)
        ).pullReadOnly()
    }

    public func synchronize() async throws -> ZoteroClientSynchronizationReport? {
        guard let connection = try await activeConnection() else {
            return nil
        }
        let client = ZoteroAPIClient(connection: connection, session: session)
        let engine = ZoteroSyncEngine(database: database, client: client)
        let metadata = try await engine.synchronize()
        guard
            let attachmentsDirectory,
            try database.loadZoteroConnectionProfile()?.canAccessFiles == true
        else {
            return ZoteroClientSynchronizationReport(metadata: metadata, attachments: nil)
        }
        let attachments = try await ZoteroAttachmentTransfer(
            database: database,
            client: client,
            attachmentsDirectory: attachmentsDirectory
        ).uploadPending()
        if attachments.uploadedCount + attachments.alreadyCurrentCount > 0 {
            _ = try await engine.pullReadOnly()
        }
        return ZoteroClientSynchronizationReport(metadata: metadata, attachments: attachments)
    }

    public func downloadAttachment(itemKey: String) async throws -> URL {
        guard let attachmentsDirectory else {
            throw ZoteroConnectionManagerError.attachmentStorageUnavailable
        }
        guard let connection = try await activeConnection() else {
            throw ZoteroConnectionManagerError.missingCredential
        }
        return try await ZoteroAttachmentTransfer(
            database: database,
            client: ZoteroAPIClient(connection: connection, session: session),
            attachmentsDirectory: attachmentsDirectory
        ).download(itemKey: itemKey)
    }

    // MARK: Private

    private let database: CitrationDatabase
    private let credentialStore: any ZoteroCredentialStore
    private let attachmentsDirectory: URL?
    private let session: URLSession
}
