import Foundation

#if canImport(UIKit) && !os(visionOS)
import UIKit

@MainActor
final class ForegroundDownloadWakeLock {
    static let shared = ForegroundDownloadWakeLock()

    private var engaged = false

    private init() {}

    func update(hasActiveForegroundDownloads: Bool, isSceneActive: Bool) {
        let shouldEngage = hasActiveForegroundDownloads && isSceneActive
        guard engaged != shouldEngage else { return }
        engaged = shouldEngage
        UIApplication.shared.isIdleTimerDisabled = shouldEngage
        Task { await logger.log("[Download][WakeLock] active=\(shouldEngage)") }
    }

    func release() {
        update(hasActiveForegroundDownloads: false, isSceneActive: false)
    }
}
#else
@MainActor
final class ForegroundDownloadWakeLock {
    static let shared = ForegroundDownloadWakeLock()

    private init() {}

    func update(hasActiveForegroundDownloads: Bool, isSceneActive: Bool) {}
    func release() {}
}
#endif
