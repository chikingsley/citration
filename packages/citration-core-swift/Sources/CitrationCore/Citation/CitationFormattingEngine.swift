import Foundation

// MARK: - CitationEngineError

public enum CitationEngineError: Error, LocalizedError, Sendable {
    case invalidInput(String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case let .invalidInput(details):
            "Invalid citation input: \(details)"
        }
    }
}

// MARK: - CitationFormattingEngine

public protocol CitationFormattingEngine: Sendable {
    func formatCluster(
        _ cluster: CitationCluster,
        items: [BCItem],
        style: CitationStyle,
        options: CitationRenderOptions
    ) async throws -> FormattedCitationCluster

    func formatBibliography(
        items: [BCItem],
        style: CitationStyle,
        options: CitationRenderOptions
    ) async throws -> FormattedBibliography
}

// MARK: - StubCitationFormatter

public struct StubCitationFormatter: CitationFormattingEngine {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public func formatCluster(
        _ cluster: CitationCluster,
        items: [BCItem],
        style: CitationStyle,
        options: CitationRenderOptions
    ) throws -> FormattedCitationCluster {
        _ = items
        guard !cluster.items.isEmpty else {
            throw CitationEngineError.invalidInput("cluster must contain at least one citation item")
        }

        let itemFragments = cluster.items.map { item in
            var parts: [String] = [item.itemID.uuidString]
            if let locator = item.locator, !locator.isEmpty {
                parts.append("loc=\(locator)")
            }
            if let prefix = item.prefix, !prefix.isEmpty {
                parts.append("prefix=\(prefix)")
            }
            if let suffix = item.suffix, !suffix.isEmpty {
                parts.append("suffix=\(suffix)")
            }
            if item.suppressAuthor {
                parts.append("suppress-author")
            }
            return parts.joined(separator: "|")
        }

        let rendered = "[\(style.id)] " + itemFragments.joined(separator: "; ")
        return FormattedCitationCluster(clusterID: cluster.id, text: rendered, format: options.format)
    }

    public func formatBibliography(
        items: [BCItem],
        style: CitationStyle,
        options: CitationRenderOptions
    ) -> FormattedBibliography {
        guard !items.isEmpty else {
            return FormattedBibliography(entries: [], format: options.format)
        }

        let entries = items.enumerated().map { index, item in
            "\(index + 1). [\(style.id)] \(item.id.uuidString)"
        }

        return FormattedBibliography(entries: entries, format: options.format)
    }
}
