import Foundation

extension String {
    func bcCollapsedWhitespace() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var bcTrimmedNonEmpty: String? {
        let normalized = bcCollapsedWhitespace()
        return normalized.isEmpty ? nil : normalized
    }
}
