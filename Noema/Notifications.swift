// Notifications.swift
import Foundation

extension Notification.Name {
    static let thinkToggled = Notification.Name("Noema.thinkToggled")
    static let embeddingModelAvailabilityChanged = Notification.Name("Noema.embeddingModelAvailabilityChanged")
    static let llamaLogMessage = Notification.Name("Noema.llamaLogMessage")
    // Posted by BackgroundDownloadManager when a background URLSession download finishes but
    // no in-memory continuation is available (e.g., after app restart). Allows controllers
    // to reconcile and finalize installs.
    static let backgroundDownloadCompleted = Notification.Name("Noema.backgroundDownloadCompleted")
}
