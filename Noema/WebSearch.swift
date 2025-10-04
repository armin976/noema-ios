// WebSearch.swift
import Foundation

// MARK: - Web Search Result Models

struct WebHit: Codable {
    let title: String
    let url: String
    let snippet: String
    let engine: String
    let score: Double?
}

// MARK: - SearXNG Response Models

struct SearXNGResponse: Decodable {
    let results: [SearXNGResult]

    init(results: [SearXNGResult]) {
        self.results = results
    }

    private enum CodingKeys: String, CodingKey {
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent([SearXNGResult].self, forKey: .results) ?? []
        self.init(results: decoded)
    }
}

struct SearXNGResult: Decodable {
    let title: String?
    let url: String?
    let content: String?
    let snippet: String?
    let engine: String?
    let engines: [String]?
    let score: Double?
}

// MARK: - SearXNG Configuration

enum SearXNGSearchConfig {
    static func endpointURL() -> URL {
        let base = AppSecrets.searxngSearchURL
        if base.path.isEmpty || base.path == "/" {
            return base.appendingPathComponent("search")
        }
        return base
    }
}

// MARK: - SearXNG Search Client

actor SearXNGSearchClient {
    func search(_ query: String, count: Int = 3, safesearch: String = "off") async throws -> [WebHit] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "Search query cannot be empty"])
        }

        let clampedCount = max(1, min(count, 5))

        var components = URLComponents(url: SearXNGSearchConfig.endpointURL(), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: String(clampedCount))
        ]

        let locale = Locale.current
        let languageTag: String? = {
            if #available(iOS 16.0, macOS 13.0, *) {
                if let languageCode = locale.language.languageCode?.identifier {
                    if let regionCode = locale.region?.identifier {
                        return "\(languageCode)-\(regionCode)"
                    }
                    return languageCode
                }
            }

            if let languageCode = locale.languageCode {
                if let regionCode = locale.regionCode {
                    return "\(languageCode)-\(regionCode)"
                }
                return languageCode
            }

            let fallback = locale.identifier.replacingOccurrences(of: "_", with: "-")
            return fallback.isEmpty ? nil : fallback
        }()

        if let languageTag {
            queryItems.append(URLQueryItem(name: "language", value: languageTag))
        }

        let safesearchLevel: String = {
            switch safesearch.lowercased() {
            case "off": return "0"
            case "strict": return "2"
            default: return "1"
            }
        }()

        queryItems.append(URLQueryItem(name: "safesearch", value: safesearchLevel))
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "Unable to construct SearXNG search URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
        NetworkKillSwitch.track(session: URLSession.shared)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let payload = try decoder.decode(SearXNGResponse.self, from: data)
            let hits = payload.results.compactMap { result -> WebHit? in
                guard let title = result.title, let url = result.url else { return nil }
                let snippet = result.snippet ?? result.content ?? ""
                let engine = result.engine ?? result.engines?.first ?? "searxng"
                return WebHit(title: title, url: url, snippet: snippet, engine: engine, score: result.score)
            }
            return Array(hits.prefix(clampedCount))

        case 400:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "Invalid request: \(errorMessage)"])
            }
            throw URLError(.badURL)

        case 429:
            throw URLError(.resourceUnavailable, userInfo: [NSLocalizedDescriptionKey: "SearXNG rate limit exceeded"])

        case 502, 503:
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "SearXNG service temporarily unavailable"])

        default:
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }
    }
}

