// WebRetrieveTool.swift
import Foundation

public struct WebRetrieveTool: Tool {
    public let name = "noema.web.retrieve"
    public let description = "Web search via Brave Search; returns web results (title, url, snippet)."
    public let schema = #"""
    { "type":"object", "properties":{
        "query":{"type":"string","description":"Search query"},
        "count":{"type":"integer","maximum":5,"minimum":1,"default":3,"description":"Number of results (1-5)"},
        "safesearch":{"type":"string","enum":["off","moderate","strict"],"default":"moderate","description":"Content filtering level"}
    }, "required":["query"] }
    """#

    public func call(args: Data) async throws -> Data {
        struct SearchArgs: Decodable { 
            let query: String
            let count: Int?
            let safesearch: String?
        }
        let input = try JSONDecoder().decode(SearchArgs.self, from: args)
        
        #if DEBUG
        await logger.log("[WebRetrieve] query=\(input.query) count=\(input.count ?? 3) safesearch=\(input.safesearch ?? "moderate")")
        #endif
        
        // Guard global availability (offline-only, disabled, or not armed)
        guard WebToolGate.isAvailable() else {
            let errorPayload = ["error": "Web search is disabled or offline-only."]
            return try JSONSerialization.data(withJSONObject: errorPayload)
        }

        do {
            let safesearch = input.safesearch ?? "moderate"
            let count = max(1, min(input.count ?? 3, 5))
            let hits = try await BraveSearchClient().search(input.query, count: count, safesearch: safesearch)
            #if DEBUG
            await logger.log("[WebRetrieve] success: \(hits.count) hits (safesearch: \(safesearch))")
            #endif
            
            return try JSONEncoder().encode(hits)
            
        } catch {
            #if DEBUG
            await logger.log("[WebRetrieve] error: \(error.localizedDescription)")
            #endif
            
            let errorPayload = ["error": String(describing: error)]
            return try JSONSerialization.data(withJSONObject: errorPayload)
        }
    }
}

