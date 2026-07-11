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

        let store: any BCItemStore
        do {
            let storeURL = try CitrationCorePaths.defaultItemStoreURL()
            store = try SwiftDataItemStore(storeURL: storeURL)
        } catch {
            fatalError("Failed to initialize legacy SwiftData item store before migration: \(error)")
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
            sessionStore: sessionStore,
            pdfDOIExtractor: pdfDOIExtractor,
            relatedWorkDiscoveryProvider: relatedWorkDiscoveryProvider,
            openAlexAPIKeyStore: openAlexAPIKeyStore
        )
    }
}
