// WebSearch.swift
import Foundation

// MARK: - Web Search Result Models

struct WebHit: Codable {
    let title: String
    let url: String
    let snippet: String
}

// MARK: - Proxy Response Models

struct ProxyResponse: Codable {
    let keyUsed: String
    let monthBucket: String
    let results: BraveSearchResponse
}

struct BraveSearchResponse: Codable {
    let web: WebResults?
}

struct WebResults: Codable {
    let results: [BraveWebResult]
}

struct BraveWebResult: Codable {
    let title: String
    let url: String
    let description: String
}

// MARK: - Request Models

struct SearchRequest: Codable {
    let query: String
    let count: Int
    let safesearch: String
}

// MARK: - Brave Search Proxy Configuration

enum BraveSearchConfig {
    enum ConfigurationError: LocalizedError {
        case missingProxyURL
        case invalidProxyURL(String)

        var errorDescription: String? {
            switch self {
            case .missingProxyURL:
                return "Brave search proxy URL is not configured. Set BRAVE_SEARCH_PROXY_URL or add BraveSearchProxyURL to Info.plist."
            case .invalidProxyURL(let value):
                return "Brave search proxy URL is invalid: \(value)."
            }
        }
    }

    static func proxyURL() throws -> URL {
        if let envValue = ProcessInfo.processInfo.environment["BRAVE_SEARCH_PROXY_URL"], !envValue.isEmpty {
            guard let url = URL(string: envValue) else {
                throw ConfigurationError.invalidProxyURL(envValue)
            }
            return url
        }

        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: "BraveSearchProxyURL") as? String, !bundleValue.isEmpty {
            guard let url = URL(string: bundleValue) else {
                throw ConfigurationError.invalidProxyURL(bundleValue)
            }
            return url
        }

        throw ConfigurationError.missingProxyURL
    }
}

// MARK: - Brave Search Client

actor BraveSearchClient {
    func search(_ query: String, count: Int = 3, safesearch: String = "off") async throws -> [WebHit] {
        // Create the request payload
        let searchRequest = SearchRequest(
            query: query,
            count: max(1, min(count, 5)), // Clamp to 5 results max
            safesearch: safesearch
        )
        
        // Create the HTTP request
        let proxyURL = try BraveSearchConfig.proxyURL()
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Encode the request body
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(searchRequest)
        
        // Perform the request (blocked when off-grid)
        if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
        NetworkKillSwitch.track(session: URLSession.shared)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        switch httpResponse.statusCode {
        case 200:
            // Success - parse the proxy response
            let decoder = JSONDecoder()
            let proxyResponse = try decoder.decode(ProxyResponse.self, from: data)
            
            // Extract web results and convert to WebHit format
            let webResults = proxyResponse.results.web?.results ?? []
            return webResults.map { result in
                WebHit(
                    title: result.title,
                    url: result.url,
                    snippet: result.description
                )
            }
            
        case 400:
            // Invalid parameters
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "Invalid request: \(errorMessage)"])
            }
            throw URLError(.badURL)
            
        case 503:
            // API keys exhausted or cooling down
            throw URLError(.resourceUnavailable, userInfo: [NSLocalizedDescriptionKey: "Search service temporarily unavailable"])
            
        case 502:
            // Upstream Brave services failed
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Search service error"])
            
        default:
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }
    }
}
