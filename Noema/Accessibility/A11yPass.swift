import SwiftUI

enum A11yPass {
    static let minimumTargetHeight: CGFloat = 44

    fileprivate struct TapTargetModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .frame(minHeight: A11yPass.minimumTargetHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
    }
}

extension View {
    func a11yTarget() -> some View {
        modifier(A11yPass.TapTargetModifier())
    }

    func a11yLabel(_ label: String) -> some View {
        accessibilityLabel(Text(label))
    }

    func a11yHint(_ hint: String) -> some View {
        accessibilityHint(Text(hint))
    }
}
