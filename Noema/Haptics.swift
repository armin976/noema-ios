#if os(iOS)
import UIKit
#if canImport(CoreHaptics)
import CoreHaptics
#endif

@MainActor
enum Haptics {
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static var notificationGenerator: UINotificationFeedbackGenerator?

    private static var supportsImpact: Bool = {
#if canImport(CoreHaptics)
        if #available(iOS 13.0, *) {
            return CHHapticEngine.capabilitiesForHardware().supportsHaptics
        }
#endif
        return false
    }()

    private static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled, supportsImpact else { return }
        if impactGenerators[style] == nil {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            impactGenerators[style] = generator
        }
        impactGenerators[style]?.impactOccurred()
        impactGenerators[style]?.prepare()
    }

    static func success() {
        guard isEnabled, supportsImpact else { return }
        if notificationGenerator == nil {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            notificationGenerator = generator
        }
        notificationGenerator?.notificationOccurred(.success)
        notificationGenerator?.prepare()
    }

    static func error() {
        guard isEnabled, supportsImpact else { return }
        if notificationGenerator == nil {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            notificationGenerator = generator
        }
        notificationGenerator?.notificationOccurred(.error)
        notificationGenerator?.prepare()
    }

    /// A lighter success cue used for low-friction completion moments.
    static func successLight() {
        impact(.soft)
    }
}
#elseif os(visionOS)
@MainActor
enum Haptics {
    static func impact(_ style: Any? = nil) {}
    static func success() {}
    static func error() {}
    static func successLight() {}
}
#else
enum Haptics {
    static func impact(_ style: Any? = nil) {}
    static func success() {}
    static func error() {}
    static func successLight() {}
}
#endif
