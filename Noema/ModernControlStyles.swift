import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    var color: Color = .accentColor
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()

        configuration.label
            .font(FontTheme.caption(size: 13))
            .tracking(0.5)
            // Trim the height a bit so the control no longer gets clipped by
            // the iOS navigation bar’s toolbar hosting view.
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                shape
                    .fill(color.opacity(isActive ? 0.12 : 0.06))
            )
            .overlay(
                shape
                    .stroke(color.opacity(isActive ? 0.9 : 0.5), lineWidth: 1)
            )
            .contentShape(shape)
            .compositingGroup() // Prevents the capsule edges from being clipped by toolbar hosting views
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ModernToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(FontTheme.body(size: 14))
            Spacer()
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.2))
                .frame(width: 40, height: 22)
                .overlay(
                    Circle()
                        .fill(.white)
                        .padding(2)
                        .shadow(radius: 1)
                        .offset(x: configuration.isOn ? 9 : -9)
                )
                .animation(.spring(response: 0.3), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
        .padding(.vertical, 4)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
    static func glass(color: Color = .accentColor, isActive: Bool = false) -> GlassButtonStyle {
        GlassButtonStyle(color: color, isActive: isActive)
    }
}

extension ToggleStyle where Self == ModernToggleStyle {
    static var modern: ModernToggleStyle { ModernToggleStyle() }
}
