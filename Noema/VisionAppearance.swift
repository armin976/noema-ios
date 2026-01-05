#if os(visionOS)
import SwiftUI

struct VisionAppearanceModifier: ViewModifier {
    let scheme: ColorScheme?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let scheme {
            content
                .preferredColorScheme(scheme)
                .environment(\.colorScheme, scheme)
        } else {
            content
        }
    }
}

extension View {
    func visionAppearance(_ scheme: ColorScheme?) -> some View {
        modifier(VisionAppearanceModifier(scheme: scheme))
    }
}

enum VisionAppearance {
    static func forcedScheme(for appearance: String) -> ColorScheme? {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}
#endif
