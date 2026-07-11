import CitrationCore
import Foundation

extension AppModel {
    static func bootstrap() -> AppModel {
        let database: CitrationDatabase
        do {
            database = try CitrationDatabase(at: CitrationCorePaths.defaultDatabaseURL())
        } catch {
            fatalError("Failed to initialize Citration database: \(error)")
        }

        let store: CitrationLibraryStore
        do {
            let applicationDirectory = try CitrationCorePaths.applicationSupportDirectory()
            let migrator = LegacyLibraryMigrator(
                database: database,
                sources: LegacyLibrarySources(applicationDirectory: applicationDirectory),
                backupDirectory: applicationDirectory.appending(path: "Legacy Backups", directoryHint: .isDirectory)
            )
            _ = try migrator.migrateSynchronously()
            store = try CitrationLibraryStore(
                database: database,
                attachmentsDirectory: applicationDirectory.appending(path: "attachments", directoryHint: .isDirectory)
            )
        } catch {
            fatalError("Failed to migrate and initialize the GRDB library: \(error)")
        }

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
        let sessionStore = KeychainAuthSessionStore()

        return AppModel(
            database: database,
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
            sessionStore: sessionStore,
            pdfDOIExtractor: pdfDOIExtractor,
            relatedWorkDiscoveryProvider: relatedWorkDiscoveryProvider,
            openAlexAPIKeyStore: openAlexAPIKeyStore
        )
    }
}
