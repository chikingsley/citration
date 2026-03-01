import Foundation
import UniformTypeIdentifiers
import BCDomain

struct LocalAttachment: Identifiable, Hashable, Sendable {
    var id: String { objectKey }
    let itemID: UUID
    let fileName: String
    let objectKey: String
    let localURL: URL
    let contentType: String
    let size: Int64
    let createdAt: Date
}

enum LocalAttachmentStorePaths {
    static func defaultBaseDirectory(
        appDirectoryName: String = "BetterCite",
        attachmentsDirectoryName: String = "attachments"
    ) throws -> URL {
        let appSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDirectory = appSupportDirectory.appendingPathComponent(appDirectoryName, isDirectory: true)
        let attachmentsDirectory = appDirectory.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        return attachmentsDirectory
    }
}

actor LocalAttachmentStore {
    private let baseDirectory: URL
    private let fileManager: FileManager

    init(baseDirectory: URL, fileManager: FileManager = .default) throws {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    func importFile(from sourceURL: URL, for item: BCItem) throws -> LocalAttachment {
        guard sourceURL.isFileURL else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let extensionPart = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension.lowercased()
        let sourceStem = sourceURL.deletingPathExtension().lastPathComponent

        let destinationDirectory = directoryURL(for: item)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let baseStem = preferredBaseName(for: item, sourceStem: sourceStem)
        let destinationFilename = uniqueFileName(
            baseStem: baseStem,
            fileExtension: extensionPart,
            in: destinationDirectory
        )

        let destinationURL = destinationDirectory.appendingPathComponent(destinationFilename)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return try metadata(for: destinationURL, itemID: item.id)
    }

    func listAttachments(for itemID: UUID) throws -> [LocalAttachment] {
        let directory = resolvedDirectoryURL(for: itemID)
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            }
            .map { try metadata(for: $0, itemID: itemID) }
            .sorted { lhs, rhs in
                lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
            }
    }

    private func directoryURL(for item: BCItem) -> URL {
        let titleSlug = slugComponent(item.title)
        let safeTitle = titleSlug.isEmpty ? "item" : titleSlug
        let directoryName = "\(item.id.uuidString)--\(safeTitle)"
        return baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func resolvedDirectoryURL(for itemID: UUID) -> URL {
        let prefix = "\(itemID.uuidString)--"

        if let entries = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            if let match = entries.first(where: { $0.lastPathComponent.hasPrefix(prefix) }) {
                return match
            }
        }

        // Backward compatibility if a legacy directory already exists.
        return baseDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true)
    }

    private func metadata(for fileURL: URL, itemID: UUID) throws -> LocalAttachment {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentTypeKey])
        let size = Int64(values.fileSize ?? 0)
        let createdAt = values.creationDate ?? .now
        let fileName = fileURL.lastPathComponent
        let objectKey = "\(itemID.uuidString)/\(fileName)"
        let contentType = values.contentType?.preferredMIMEType ?? "application/octet-stream"

        return LocalAttachment(
            itemID: itemID,
            fileName: fileName,
            objectKey: objectKey,
            localURL: fileURL,
            contentType: contentType,
            size: size,
            createdAt: createdAt
        )
    }

    private func preferredBaseName(for item: BCItem, sourceStem: String) -> String {
        let rawTitle = item.title == "Untitled Item" ? sourceStem : item.title
        let title = slugComponent(rawTitle)
        let author = slugComponent(item.creators.first?.familyName ?? "")
        let year = item.publicationYear.map(String.init) ?? ""

        var pieces = [String]()
        if !author.isEmpty {
            pieces.append(author)
        }
        if !year.isEmpty {
            pieces.append(year)
        }
        if !title.isEmpty {
            pieces.append(title)
        }

        let base = pieces.joined(separator: "_")
        if base.isEmpty {
            return "attachment"
        }
        return String(base.prefix(96))
    }

    private func uniqueFileName(baseStem: String, fileExtension: String, in directory: URL) -> String {
        var candidate = "\(baseStem).\(fileExtension)"
        var index = 2

        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(baseStem)-\(index).\(fileExtension)"
            index += 1
        }

        return candidate
    }

    private func slugComponent(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let folded = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let normalized = folded.replacingOccurrences(
            of: "[^a-zA-Z0-9]+",
            with: "-",
            options: .regularExpression
        )

        return normalized
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
    }
}
