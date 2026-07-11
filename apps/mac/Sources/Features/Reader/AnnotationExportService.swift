import CitrationCore
import CryptoKit
import Foundation
import PDFKit

// MARK: - AnnotationExportError

enum AnnotationExportError: Error {
    case invalidAnnotationPosition
    case unreadableAttachment
    case unsupportedAnnotatedCopy
}

// MARK: - AnnotationExportService

enum AnnotationExportService {
    static func sidecarData(
        attachment: LocalAttachment,
        annotations: [SynchronizedLibraryAnnotation]
    ) async throws -> Data {
        let digest = try await SHA256Digest.read(from: attachment.localURL)
        let sidecar = try AnnotationSidecar(
            schemaVersion: 1,
            source: AnnotationSidecarSource(
                fileName: attachment.fileName,
                objectKey: attachment.objectKey,
                sha256: digest,
                byteCount: attachment.size
            ),
            annotations: annotations
                .sorted { lhs, rhs in
                    if lhs.sortIndex == rhs.sortIndex {
                        return lhs.identity.objectKey < rhs.identity.objectKey
                    }
                    return lhs.sortIndex < rhs.sortIndex
                }
                .map(AnnotationSidecarRecord.init)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(sidecar)
    }

    @MainActor
    static func annotatedPDFData(
        attachment: LocalAttachment,
        annotations: [SynchronizedLibraryAnnotation]
    ) throws -> Data {
        guard attachment.documentFormat == .pdf else {
            throw AnnotationExportError.unsupportedAnnotatedCopy
        }
        guard
            let sourceData = try? Data(contentsOf: attachment.localURL),
            let document = PDFDocument(data: sourceData)
        else {
            throw AnnotationExportError.unreadableAttachment
        }
        for annotation in annotations.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            _ = ZoteroPDFAnnotationRenderer.render(annotation, in: document)
        }
        guard let exported = document.dataRepresentation() else {
            throw AnnotationExportError.unreadableAttachment
        }
        return exported
    }
}

// MARK: - AnnotationSidecar

private struct AnnotationSidecar: Codable {
    let schemaVersion: Int
    let source: AnnotationSidecarSource
    let annotations: [AnnotationSidecarRecord]
}

// MARK: - AnnotationSidecarSource

private struct AnnotationSidecarSource: Codable {
    let fileName: String
    let objectKey: String
    let sha256: String
    let byteCount: Int64
}

// MARK: - AnnotationSidecarRecord

private struct AnnotationSidecarRecord: Codable {
    // MARK: Lifecycle

    init(_ annotation: SynchronizedLibraryAnnotation) throws {
        guard
            let positionData = annotation.positionJSON.data(using: .utf8),
            let position = try? ZoteroJSON.decode(positionData)
        else {
            throw AnnotationExportError.invalidAnnotationPosition
        }
        key = annotation.identity.objectKey
        version = annotation.version
        type = annotation.type
        color = annotation.color
        pageLabel = annotation.pageLabel
        sortIndex = annotation.sortIndex
        text = annotation.text
        comment = annotation.comment
        self.position = position
        tags = annotation.tags.map { AnnotationSidecarTag(value: $0.value, type: $0.type) }
        createdAt = annotation.createdAt
        updatedAt = annotation.updatedAt
    }

    // MARK: Internal

    let key: String
    let version: Int64
    let type: String
    let color: String
    let pageLabel: String
    let sortIndex: String
    let text: String
    let comment: String
    let position: JSONValue
    let tags: [AnnotationSidecarTag]
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - AnnotationSidecarTag

private struct AnnotationSidecarTag: Codable {
    let value: String
    let type: Int?
}

// MARK: - SHA256Digest

private enum SHA256Digest {
    static func read(from url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var digest = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                digest.update(data: data)
            }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
