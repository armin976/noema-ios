import SwiftUI

/// A reusable “liquid glass” pill background for inputs and controls.
struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: UIConstants.extraLargeCornerRadius, style: .continuous)
        content
            .glassifyIfAvailable(in: shape)
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.7),
                                Color.accentColor.opacity(0.4),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                shape
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.75)
                    .blendMode(.plusLighter)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

extension View {
    /// Applies a pill-shaped, frosted glass background suitable for an input field.
    func glassPill() -> some View { modifier(GlassPill()) }
}
