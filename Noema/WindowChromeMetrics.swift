#if os(macOS)
import AppKit

@MainActor
enum WindowChromeMetrics {
    private static var cachedTitlebarHeight: CGFloat = 36

    static var titlebarHeight: CGFloat { cachedTitlebarHeight }

    static func update(from window: NSWindow) {
        let delta = window.frame.height - window.contentLayoutRect.height
        guard delta.isFinite, delta > 0 else { return }
        if abs(cachedTitlebarHeight - delta) > 0.5 {
            cachedTitlebarHeight = delta
            NotificationCenter.default.post(name: .windowChromeMetricsDidChange, object: nil)
        } else {
            cachedTitlebarHeight = delta
        }
    }
}

extension Notification.Name {
    static let windowChromeMetricsDidChange = Notification.Name("NoemaWindowChromeMetricsDidChange")
}
#endif
