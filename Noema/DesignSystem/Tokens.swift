import SwiftUI

enum Tokens {
    enum Colors {
        static let background = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let accent = Color.accentColor
        static let danger = Color(uiColor: .systemRed)
        static let muted = Color(uiColor: .secondaryLabel)
    }

    enum Typography {
        static let title = Font.system(.title3, design: .rounded).weight(.semibold)
        static let body = Font.system(.body, design: .default)
        static let caption = Font.system(.footnote, design: .default)
        static let mono = Font.system(.callout, design: .monospaced)
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 24
    }

    enum Elevation {
        static let level1 = ElevationStyle(radius: 10, y: 4, opacity: 0.06)
        static let level2 = ElevationStyle(radius: 18, y: 8, opacity: 0.12)
    }

    struct ElevationStyle {
        let radius: CGFloat
        let y: CGFloat
        let opacity: Double
    }
}

extension View {
    func elevation(_ style: Tokens.ElevationStyle) -> some View {
        shadow(color: .black.opacity(style.opacity), radius: style.radius, x: 0, y: style.y)
    }
}
