// ToolRouter+WebRetrieve.swift
import Foundation

@MainActor
func handle_noema_web_retrieve(_ argsJSON: Data, contextLimit: Double = 4096) async -> Data {
    func userFacingMessage(for error: Error) -> String {
        let ns = error as NSError
        let code = (error as? URLError)?.code ?? URLError.Code(rawValue: ns.code)
        switch code {
        case .timedOut:
            return "Web search timed out. Please try again."
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
            return "Web search is unavailable right now. Check your internet connection and try again."
        case .cancelled:
            return "Web search was cancelled."
        default:
            let localized = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if localized.isEmpty || localized.lowercased().contains("nsurlerrordomain") {
                return "Web search failed. Please try again."
            }
            return localized
        }
    }

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
        
        let safesearch = args.safesearch ?? "moderate"
        let count = max(1, min(args.count ?? 3, 5))
        let hits = try await SearXNGSearchClient().search(args.query, count: count, safesearch: safesearch)

        return try JSONEncoder().encode(hits)
    } catch {
        #if DEBUG
        await logger.log("[WebRetrieve][Router] error: \(String(describing: error))")
        #endif
        let payload = ["error": userFacingMessage(for: error)]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            return data
        }
        return Data("{\"error\":\"Web search failed. Please try again.\"}".utf8)
    }
}
