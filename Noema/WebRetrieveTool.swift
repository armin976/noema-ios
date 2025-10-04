// WebRetrieveTool.swift
import Foundation

public struct WebRetrieveTool: Tool {
    public let name = "noema.web.retrieve"
    public let description = "Web search via SearXNG; returns web results (title, url, snippet)."
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
        let requestedCount = input.count ?? 3
        let requestedSafesearch = input.safesearch ?? "moderate"
        let requestedFormat = "json"
        await logger.log(
            """
            [WebRetrieve] ⇢ request
              query: \(input.query)
              count: \(requestedCount)
              safesearch: \(requestedSafesearch)
              format: \(requestedFormat)
            """
        )
        #endif
        
        // Guard global availability (offline-only, disabled, or not armed)
        guard WebToolGate.isAvailable() else {
            let errorPayload = ["error": "Web search is disabled or offline-only."]
            return try JSONSerialization.data(withJSONObject: errorPayload)
        }

        do {
            let safesearch = input.safesearch ?? "moderate"
            let count = max(1, min(input.count ?? 3, 5))
            let hits = try await SearXNGSearchClient().search(input.query, count: count, safesearch: safesearch)
            #if DEBUG
            let summaries = hits.enumerated().map { index, hit in
                "  \(index + 1). \(hit.title)\n     url: \(hit.url)\n     engine: \(hit.engine)"
            }.joined(separator: "\n")
            await logger.log(
                """
                [WebRetrieve] ⇠ response
                  hits: \(hits.count)
                  safesearch: \(safesearch)
                \(summaries.isEmpty ? "  <no hits>" : summaries)
                """
            )
            #endif
            
            return try JSONEncoder().encode(hits)
            
        } catch {
            #if DEBUG
            await logger.log(
                """
                [WebRetrieve] ❌ error
                  query: \(input.query)
                  message: \(error.localizedDescription)
                """
            )
            #endif

            let message: String = {
                if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
                    return localized
                }
                return error.localizedDescription
            }()

            let errorPayload = ["error": message]
            return try JSONSerialization.data(withJSONObject: errorPayload)
        }
    }
}
