#if os(iOS)
import UIKit
#if canImport(CoreHaptics)
import CoreHaptics
#endif

@MainActor
enum Haptics {
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    private static var supportsImpact: Bool = {
#if canImport(CoreHaptics)
        if #available(iOS 13.0, *) {
            return CHHapticEngine.capabilitiesForHardware().supportsHaptics
        }
#endif
        return false
    }()

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard supportsImpact else { return }
        if impactGenerators[style] == nil {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            impactGenerators[style] = generator
        }
        impactGenerators[style]?.impactOccurred()
    }
}
#elseif os(visionOS)
@MainActor
enum Haptics {
    static func impact(_ style: Any? = nil) {}
}
#else
enum Haptics {
    static func impact(_ style: Any? = nil) {}
}
#endif
