import AppKit
import CitrationCore

extension AnnotationColor {
    var nsColor: NSColor {
        switch self {
        case .yellow:
            .systemYellow
        case .green:
            .systemGreen
        case .blue:
            .systemBlue
        case .pink:
            .systemPink
        case .purple:
            .systemPurple
        }
    }
}
