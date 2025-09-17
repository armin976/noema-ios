// ToolRouter+WebRetrieve.swift
import Foundation

@MainActor
func handle_noema_web_retrieve(_ argsJSON: Data, contextLimit: Double = 4096) async -> Data {
    do {
        struct SearchArgs: Decodable { 
            let query: String
            let count: Int?
            let safesearch: String?
        }
        let args = try JSONDecoder().decode(SearchArgs.self, from: argsJSON)
        
        // Check if web search is available (includes gate checks)
        guard WebToolGate.isAvailable() else {
            let errorPayload = ["error": "Web search is disabled or offline-only."]
            return try JSONSerialization.data(withJSONObject: errorPayload)
        }
        
        // Check usage limits
        let usageTracker = SearchUsageTracker.shared
        let settings = SettingsStore.shared
        
        if !settings.hasUnlimitedSearches && !usageTracker.canPerformSearch() {
            let errorPayload = ["error": "Daily search limit reached (5 searches). Upgrade for unlimited searches."]
            return try JSONSerialization.data(withJSONObject: errorPayload)
        }
        
        let safesearch = args.safesearch ?? "moderate"
        let count = max(1, min(args.count ?? 3, 5))
        let hits = try await BraveSearchClient().search(args.query, count: count, safesearch: safesearch)
        
        // Increment usage counter on successful search
        if !settings.hasUnlimitedSearches {
            usageTracker.incrementUsage()
        }
        
        return try JSONEncoder().encode(hits)
    } catch {
        let payload = ["error": String(describing: error)]
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}
