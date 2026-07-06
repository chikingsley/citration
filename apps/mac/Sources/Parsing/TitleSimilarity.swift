import Foundation

/// Guards title-search metadata results: a provider's best match is
/// only trusted when its title actually resembles the query, so a
/// search for an obscure book cannot silently adopt the metadata of
/// whatever ranked first.
enum TitleSimilarity {
    // MARK: Internal

    static func isAcceptableMatch(query: String, candidate: String) -> Bool {
        let queryTokens = tokens(in: query)
        let candidateTokens = tokens(in: candidate)
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else {
            return false
        }

        let intersection = queryTokens.intersection(candidateTokens).count
        let union = queryTokens.union(candidateTokens).count
        let jaccard = Double(intersection) / Double(union)
        return jaccard >= 0.6
    }

    // MARK: Private

    private static func tokens(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }
}
