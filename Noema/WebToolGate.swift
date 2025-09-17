// WebToolGate.swift
import Foundation

struct WebToolGate {
    // Background-safe gate that avoids MainActor by reading persisted defaults directly.
    static func isAvailable(currentFormat: ModelFormat? = nil) -> Bool {
        let d = UserDefaults.standard
        let enabled = d.object(forKey: "webSearchEnabled") as? Bool ?? true
        let offGrid = d.object(forKey: "offGrid") as? Bool ?? false
        // Keep kill switch in sync even if settings change outside SettingsView
        NetworkKillSwitch.setEnabled(offGrid)
        let armed = d.object(forKey: "webSearchArmed") as? Bool ?? false
        let hasUnlimited = d.object(forKey: "hasUnlimitedSearches") as? Bool ?? false
        // Datasets take precedence: when a dataset is selected or indexing, web search is disabled.
        let selectedDatasetID = d.string(forKey: "selectedDatasetID") ?? ""
        let indexingDatasetID = d.string(forKey: "indexingDatasetIDPersisted") ?? ""
        let datasetActiveOrIndexing = (!selectedDatasetID.isEmpty) || (!indexingDatasetID.isEmpty)

        // Resolve current model format (fallback to persisted if not provided)
        var fmt = currentFormat
        if fmt == nil, let fmtStr = d.string(forKey: "currentModelFormat"), let f = ModelFormat(rawValue: fmtStr) {
            fmt = f
        }

        // Only allow when the loaded model supports function calling (from model card/capability detector)
        // Leap SLM models are intentionally blocked from using web search.
        if let f = fmt, f == .slm { return false }
        let supportsFunctionCalling = d.object(forKey: "currentModelSupportsFunctionCalling") as? Bool ?? false
        if supportsFunctionCalling == false { return false }

        // Basic availability check (dataset use overrides and disables web search)
        let basicAvailable = enabled && !offGrid && armed && !datasetActiveOrIndexing

        // If user has unlimited searches, no need to check usage
        if hasUnlimited {
            return basicAvailable
        }

        // For limited users, also check if they haven't hit the limit
        // Note: This is a basic check - the actual enforcement happens in handle_noema_web_retrieve
        return basicAvailable
    }
}
