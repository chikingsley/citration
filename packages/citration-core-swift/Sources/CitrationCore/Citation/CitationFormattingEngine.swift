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
