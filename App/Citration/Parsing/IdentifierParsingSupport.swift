import CitrationCore
import Foundation

func dedupeIdentifiersPreservingOrder(_ identifiers: [Identifier]) -> [Identifier] {
    var seen = Set<String>()
    var ordered = [Identifier]()

    for identifier in identifiers {
        let key = "\(identifier.type.rawValue):\(identifier.value.lowercased())"
        if seen.insert(key).inserted {
            ordered.append(identifier)
        }
    }

    return ordered
}

/// Builds a regex for a static pattern; traps on invalid patterns since they
/// are programmer error, not runtime input.
func makeStaticRegex(pattern: String, name: String) -> NSRegularExpression {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        fatalError("Invalid \(name) regex pattern: \(pattern)")
    }
    return regex
}
