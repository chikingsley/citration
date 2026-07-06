import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let citrationEPUB: UTType = .init(importedAs: "org.idpf.epub-container")
}

// MARK: - FileURLDropDelegate

struct FileURLDropDelegate: DropDelegate {
    // MARK: Internal

    let onTargetedChange: (Bool) -> Void
    let onDropURLs: ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info _: DropInfo) {
        onTargetedChange(true)
    }

    func dropExited(info _: DropInfo) {
        onTargetedChange(false)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetedChange(false)

        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            return false
        }

        Self.loadFileURLs(from: providers) { urls in
            onDropURLs(urls)
        }
        return true
    }

    // MARK: Private

    private final class URLCollector: @unchecked Sendable {
        // MARK: Internal

        func append(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        func snapshot() -> [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }

        // MARK: Private

        private let lock: NSLock = .init()
        private var urls: [URL] = []
    }

    private nonisolated static func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let collector = URLCollector()

        for provider in providers {
            group.enter()
            loadSingleFileURL(from: provider) { url in
                defer { group.leave() }
                guard let url, url.isFileURL else {
                    return
                }
                collector.append(url)
            }
        }

        group.notify(queue: .main) {
            completion(Self.dedupeFileURLs(collector.snapshot()))
        }
    }

    private nonisolated static func loadSingleFileURL(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) {
        if provider.canLoadObject(ofClass: NSURL.self) {
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let nsURL = object as? NSURL {
                    completion(nsURL as URL)
                } else {
                    completion(nil)
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                completion(Self.parseFileURL(from: item))
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _, _ in
                completion(url)
            }
            return
        }

        completion(nil)
    }

    private nonisolated static func parseFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let nsURL = item as? NSURL {
            return nsURL as URL
        }
        if let urls = item as? [URL] {
            return urls.first
        }
        if let nsURLs = item as? [NSURL] {
            return nsURLs.first as URL?
        }
        if let string = item as? String {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let string = item as? NSString {
            return URL(string: String(string).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if
            let data = item as? Data,
            let fileURL = URL(dataRepresentation: data, relativeTo: nil),
            fileURL.isFileURL
        {
            return fileURL
        }
        if
            let data = item as? Data,
            let string = String(data: data, encoding: .utf8)
        {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private nonisolated static func dedupeFileURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var output = [URL]()

        for url in urls {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                output.append(standardized)
            }
        }
        return output
    }
}
