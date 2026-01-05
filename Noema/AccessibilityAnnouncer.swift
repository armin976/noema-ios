import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
enum AccessibilityAnnouncer {
    static func announce(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

#if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: trimmed)
#elseif canImport(AppKit)
        let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: trimmed,
            .priority: NSAccessibilityPriorityLevel.high
        ]
        NSAccessibility.post(
            element: NSApp ?? NSAccessibilityElement(),
            notification: .announcementRequested,
            userInfo: userInfo
        )
#else
        _ = trimmed
#endif
    }

    static func announceLocalized(_ key: String, locale: Locale = LocalizationManager.preferredLocale()) {
        announce(String(localized: String.LocalizationValue(key), locale: locale))
    }
}
