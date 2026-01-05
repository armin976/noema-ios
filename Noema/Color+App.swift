import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Color {
    static var detailSheetBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    static var heroCardBackground: Color {
        #if os(macOS)
        // Lighter/Darker background for high contrast
        Color(nsColor: .textBackgroundColor).opacity(0.5)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }

    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    static var quantTileBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    static var quantTileBorder: Color {
        #if os(macOS)
        Color(nsColor: NSColor.separatorColor.withAlphaComponent(0.08))
        #else
        Color.black.opacity(0.05)
        #endif
    }

    static var visionAccent: Color {
#if os(macOS)
        Color(nsColor: .systemYellow)
#else
        Color(.systemYellow)
#endif
    }

    static var moeAccent: Color {
#if os(macOS)
        Color(nsColor: .systemOrange)
#else
        Color(.systemOrange)
#endif
    }
}
