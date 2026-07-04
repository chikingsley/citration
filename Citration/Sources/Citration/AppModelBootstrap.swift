import CitrationCore

extension AppModel {
    static func bootstrap() -> AppModel {
        let store: any BCItemStore
        do {
            let storeURL = try CitrationCorePaths.defaultItemStoreURL()
            store = try SwiftDataItemStore(storeURL: storeURL)
        }
        catch {
            assertionFailure("Failed to initialize SwiftData item store: \(error)")
            store = InMemoryItemStore()
        }

        let providers: [any MetadataProvider] = [
            ArXivMetadataProvider(),
            CrossrefDOIMetadataProvider(),
            OpenLibraryISBNMetadataProvider()
        ]
        let metadataRegistry = MetadataProviderRegistry(providers: providers)
        let citationFormatter = StubCitationFormatter()
        let pdfDOIExtractor = MuPDFDOIExtractor()
        let storageConnectors = [
            StorageConnector(name: "Local Files", type: .local, bucket: "local", isDefault: true)
        ]
        let sessionStore = KeychainAuthSessionStore()

        return AppModel(
            store: store,
            metadataRegistry: metadataRegistry,
            citationFormatter: citationFormatter,
            storageConnectors: storageConnectors,
            sessionStore: sessionStore,
            pdfDOIExtractor: pdfDOIExtractor
        )
    }
}
