import CitrationCore
import Foundation

extension AppModel {
    static func bootstrap() -> AppModel {
        let (database, store, attachmentsDirectory) = makePersistence()

        let providers: [any MetadataProvider] = [
            ArXivMetadataProvider(),
            CrossrefDOIMetadataProvider(),
            OpenLibraryISBNMetadataProvider(),
            OpenLibraryTitleSearchMetadataProvider(),
        ]
        let metadataRegistry = MetadataProviderRegistry(providers: providers)
        let citationFormatter = CSLCitationFormatter()
        let pdfDOIExtractor = PDFKitDOIExtractor()
        let openAlexAPIKeyStore = FileAPIKeyStore()
        let openAlexCredentialSource = OpenAlexCredentialSource(keyStore: openAlexAPIKeyStore)
        let relatedWorkDiscoveryProvider = OpenAlexRelatedWorkProvider(apiKeyProvider: openAlexCredentialSource)
        let storageConnectors = [
            StorageConnector(name: "Local Files", type: .local, bucket: "local", isDefault: true)
        ]
        let connectionManager = ZoteroConnectionManager(
            database: database,
            credentialStore: FileZoteroCredentialStore(),
            attachmentsDirectory: attachmentsDirectory
        )

        return AppModel(
            database: database,
            connectionManager: connectionManager,
            store: store,
            metadataRegistry: metadataRegistry,
            citationFormatter: citationFormatter,
            storageConnectors: storageConnectors,
            attachmentStore: store,
            annotationStore: store,
            collectionStore: store,
            noteStore: store,
            relationshipStore: store,
            readerProgressStore: store,
            pdfDOIExtractor: pdfDOIExtractor,
            relatedWorkDiscoveryProvider: relatedWorkDiscoveryProvider,
            openAlexAPIKeyStore: openAlexAPIKeyStore
        )
    }

    private static func makePersistence() -> (CitrationDatabase, CitrationLibraryStore, URL) {
        do {
            let database = try CitrationDatabase(at: CitrationCorePaths.defaultDatabaseURL())
            let applicationDirectory = try CitrationCorePaths.applicationSupportDirectory()
            let migrator = LegacyLibraryMigrator(
                database: database,
                sources: LegacyLibrarySources(applicationDirectory: applicationDirectory),
                backupDirectory: applicationDirectory.appending(path: "Legacy Backups", directoryHint: .isDirectory)
            )
            _ = try migrator.migrateSynchronously()
            let connectionProfile = try database.loadZoteroConnectionProfile()
            let attachmentsDirectory = applicationDirectory.appending(path: "attachments", directoryHint: .isDirectory)
            let store = try CitrationLibraryStore(
                database: database,
                attachmentsDirectory: attachmentsDirectory,
                libraryIdentity: connectionProfile?.libraryIdentity ?? .init(type: "local", remoteID: 0),
                libraryName: connectionProfile?.displayName ?? "Local Library"
            )
            return (database, store, attachmentsDirectory)
        } catch {
            fatalError("Failed to migrate and initialize the GRDB library: \(error)")
        }
    }
}
