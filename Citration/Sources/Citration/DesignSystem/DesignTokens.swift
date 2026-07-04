import SwiftUI

public enum BCSpacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xLarge: CGFloat = 24
}

public enum BCRadius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
}

public enum BCColor {
    public static let accent = Color(
        light: Color(red: 0.10, green: 0.40, blue: 0.86),
        dark: Color(red: 0.35, green: 0.60, blue: 1.00)
    )
    public static let accentPressed = Color(
        light: Color(red: 0.08, green: 0.32, blue: 0.72),
        dark: Color(red: 0.28, green: 0.50, blue: 0.92)
    )
    public static let panelBackground = Color(
        light: Color(white: 0.97),
        dark: Color(white: 0.17)
    )
    public static let panelBorder = Color(
        light: Color.black.opacity(0.10),
        dark: Color.white.opacity(0.12)
    )
    public static let badgeBackground = Color.accentColor.opacity(0.14)
}

public enum BCTypography {
    public static let title = Font.title3.weight(.semibold)
    public static let subtitle = Font.subheadline.weight(.medium)
    public static let body = Font.body
    public static let caption = Font.caption
}

public extension Color {
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}
