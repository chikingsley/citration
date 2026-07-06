import Foundation

// MARK: - MetadataProviderError

public enum MetadataProviderError: Error, LocalizedError, Sendable {
    case invalidRequest(String)
    case providerFailure(provider: String, details: String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case let .invalidRequest(details):
            "Invalid metadata request: \(details)"
        case let .providerFailure(provider, details):
            "Metadata provider '\(provider)' failed: \(details)"
        }
    }
}

// MARK: - MetadataProvider

public protocol MetadataProvider: Sendable {
    var name: String { get }
    func resolve(_ request: MetadataResolutionRequest) async throws -> [CanonicalMetadataRecord]
}

// MARK: - MetadataProviderRegistry

public struct MetadataProviderRegistry: Sendable {
    // MARK: Lifecycle

    public init(providers: [any MetadataProvider]) {
        self.providers = providers
    }

    // MARK: Public

    public func resolveAll(_ request: MetadataResolutionRequest) async -> MetadataResolutionResult {
        var records = [CanonicalMetadataRecord]()
        var warnings = [String]()

        for provider in providers {
            do {
                let providerRecords = try await provider.resolve(request)
                records.append(contentsOf: providerRecords)
            } catch {
                warnings.append("\(provider.name): \(error.localizedDescription)")
            }
        }

        let conflicts = detectConflicts(in: records)
        let deduped = deduplicate(records)
        return MetadataResolutionResult(records: deduped, warnings: warnings, conflicts: conflicts)
    }

    // MARK: Private

    private let providers: [any MetadataProvider]

    private func deduplicate(_ records: [CanonicalMetadataRecord]) -> [CanonicalMetadataRecord] {
        var bestByKey = [String: CanonicalMetadataRecord]()

        for record in records {
            let key = dedupeKey(for: record)
            if let existing = bestByKey[key] {
                if record.confidence > existing.confidence {
                    bestByKey[key] = record
                }
            } else {
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

    private func detectConflicts(in records: [CanonicalMetadataRecord]) -> [MetadataResolutionConflict] {
        let groupedRecords = Dictionary(grouping: records, by: dedupeKey(for:))
        return groupedRecords.values.flatMap(conflictsInGroup)
    }

    private func conflictsInGroup(_ records: [CanonicalMetadataRecord]) -> [MetadataResolutionConflict] {
        guard
            records.count > 1,
            let preferred = records.max(by: { $0.confidence < $1.confidence })
        else {
            return []
        }

        return records
            .filter { $0.id != preferred.id }
            .flatMap { conflicts(preferred: preferred, alternate: $0) }
    }

    private func conflicts(
        preferred: CanonicalMetadataRecord,
        alternate: CanonicalMetadataRecord
    ) -> [MetadataResolutionConflict] {
        var conflicts = [MetadataResolutionConflict]()
        appendStringConflict(.title, preferred.title, alternate.title, preferred, alternate, to: &conflicts)
        appendYearConflict(preferred, alternate, to: &conflicts)
        appendItemTypeConflict(preferred, alternate, to: &conflicts)
        return conflicts
    }

    private func appendStringConflict(
        _ field: MetadataConflictField,
        _ preferredValue: String,
        _ alternateValue: String,
        _ preferred: CanonicalMetadataRecord,
        _ alternate: CanonicalMetadataRecord,
        to conflicts: inout [MetadataResolutionConflict]
    ) {
        guard normalizedComparableString(preferredValue) != normalizedComparableString(alternateValue) else {
            return
        }

        conflicts.append(
            conflict(
                field,
                preferredValue: preferredValue,
                alternateValue: alternateValue,
                preferred: preferred,
                alternate: alternate
            )
        )
    }

    private func appendYearConflict(
        _ preferred: CanonicalMetadataRecord,
        _ alternate: CanonicalMetadataRecord,
        to conflicts: inout [MetadataResolutionConflict]
    ) {
        guard
            let preferredYear = preferred.publicationYear,
            let alternateYear = alternate.publicationYear,
            preferredYear != alternateYear
        else {
            return
        }

        conflicts.append(
            conflict(
                .publicationYear,
                preferredValue: String(preferredYear),
                alternateValue: String(alternateYear),
                preferred: preferred,
                alternate: alternate
            )
        )
    }

    private func appendItemTypeConflict(
        _ preferred: CanonicalMetadataRecord,
        _ alternate: CanonicalMetadataRecord,
        to conflicts: inout [MetadataResolutionConflict]
    ) {
        guard
            preferred.itemType != .unknown,
            alternate.itemType != .unknown,
            preferred.itemType != alternate.itemType
        else {
            return
        }

        conflicts.append(
            conflict(
                .itemType,
                preferredValue: preferred.itemType.rawValue,
                alternateValue: alternate.itemType.rawValue,
                preferred: preferred,
                alternate: alternate
            )
        )
    }

    private func conflict(
        _ field: MetadataConflictField,
        preferredValue: String,
        alternateValue: String,
        preferred: CanonicalMetadataRecord,
        alternate: CanonicalMetadataRecord
    ) -> MetadataResolutionConflict {
        MetadataResolutionConflict(
            field: field,
            preferredValue: preferredValue.trimmingCharacters(in: .whitespacesAndNewlines),
            alternateValue: alternateValue.trimmingCharacters(in: .whitespacesAndNewlines),
            preferredProvider: preferred.provenance.providerName,
            alternateProvider: alternate.provenance.providerName
        )
    }

    private func normalizedComparableString(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}

// MARK: - NoopMetadataProvider

public struct NoopMetadataProvider: MetadataProvider {
    // MARK: Lifecycle

    public init(name: String = "noop") {
        self.name = name
    }

    // MARK: Public

    public let name: String

    public func resolve(_ request: MetadataResolutionRequest) -> [CanonicalMetadataRecord] {
        _ = request
        return []
    }
}
