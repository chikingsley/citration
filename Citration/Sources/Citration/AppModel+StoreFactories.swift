import Foundation

extension AppModel {
    static func makeAttachmentStore() -> LocalAttachmentStore {
        do {
            let baseDirectory = try LocalAttachmentStorePaths.defaultBaseDirectory()
            return try LocalAttachmentStore(baseDirectory: baseDirectory)
        }
        catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("citration", isDirectory: true)
                .appendingPathComponent("attachments", isDirectory: true)
            do {
                return try LocalAttachmentStore(baseDirectory: fallback)
            }
            catch {
                fatalError("Unable to initialize attachment store: \(error)")
            }
        }
    }

    static func makeAnnotationStore() -> LocalAnnotationStore {
        do {
            let storeURL = try LocalAnnotationStorePaths.defaultStoreURL()
            return try LocalAnnotationStore(storeURL: storeURL)
        }
        catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("citration", isDirectory: true)
                .appendingPathComponent("annotations.json")
            do {
                return try LocalAnnotationStore(storeURL: fallback)
            }
            catch {
                fatalError("Unable to initialize annotation store: \(error)")
            }
        }
    }

    static func makeCollectionStore() -> LocalCollectionStore {
        do {
            let storeURL = try LocalCollectionStorePaths.defaultStoreURL()
            return try LocalCollectionStore(storeURL: storeURL)
        }
        catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("citration", isDirectory: true)
                .appendingPathComponent("collections.json")
            do {
                return try LocalCollectionStore(storeURL: fallback)
            }
            catch {
                fatalError("Unable to initialize collection store: \(error)")
            }
        }
    }
}
