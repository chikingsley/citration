import Foundation

public enum MetadataProviderError: Error, LocalizedError, Sendable {
    case invalidRequest(String)
    case providerFailure(provider: String, details: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let details):
            return "Invalid metadata request: \(details)"
        case .providerFailure(let provider, let details):
            return "Metadata provider '\(provider)' failed: \(details)"
        }
    }
}

public protocol MetadataProvider: Sendable {
    var name: String { get }
    func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord]
}

public struct MetadataProviderRegistry: Sendable {
    private let providers: [any MetadataProvider]

    public init(providers: [any MetadataProvider]) {
        self.providers = providers
    }

    public func resolveAll(_ request: MetadataResolutionRequest) async -> MetadataResolutionResult {
        var records: [CanonicalMetadataRecord] = []
        var warnings: [String] = []

        for provider in providers {
            do {
                let providerRecords = try await provider.resolve(request)
                records.append(contentsOf: providerRecords)
            }
            catch {
                warnings.append("\(provider.name): \(error.localizedDescription)")
            }
        }

        let deduped = deduplicate(records)
        return MetadataResolutionResult(records: deduped, warnings: warnings)
    }

    private func deduplicate(_ records: [CanonicalMetadataRecord]) -> [CanonicalMetadataRecord] {
        var bestByKey: [String: CanonicalMetadataRecord] = [:]

        for record in records {
            let key = dedupeKey(for: record)
            if let existing = bestByKey[key] {
                if record.confidence > existing.confidence {
                    bestByKey[key] = record
                }
            }
            else {
                bestByKey[key] = record
            }
        }

        return Array(bestByKey.values)
    }

    private func dedupeKey(for record: CanonicalMetadataRecord) -> String {
        if let primary = record.identifiers.first {
            return "\(primary.type.rawValue):\(primary.value.lowercased())"
        }

        let normalizedTitle = record.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let year = record.publicationYear.map(String.init) ?? "unknown"
        return "title:\(normalizedTitle)|year:\(year)"
    }
}

public struct NoopMetadataProvider: MetadataProvider {
    public let name: String

    public init(name: String = "noop") {
        self.name = name
    }

    public func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord] {
        _ = request
        return []
    }
}
