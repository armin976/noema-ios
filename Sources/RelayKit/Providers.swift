import Foundation

public struct LMStudioClient: InferenceProvider {
    public var baseURL: URL
    public var model: String
    public var apiKey: String?

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:1234")!,
        model: String = "llama-3-8b-instruct",
        apiKey: String? = nil
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    public func generateReply(for env: RelayEnvelope) async throws -> String {
        let url = baseURL.appendingPathComponent("v1/chat/completions")
        let messages = env.messages.map { ["role": $0.role, "content": $0.text] }
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": Double(env.parameters["temperature"] ?? "0.7") ?? 0.7
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey {
            request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw InferenceError.network(message)
        }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }
}

public struct OllamaClient: InferenceProvider {
    public var baseURL: URL
    public var model: String

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        model: String = "llama3"
    ) {
        self.baseURL = baseURL
        self.model = model
    }

    public func generateReply(for env: RelayEnvelope) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")
        let messages = env.messages.map { ["role": $0.role, "content": $0.text] }
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "options": [
                "temperature": Double(env.parameters["temperature"] ?? "0.7") ?? 0.7
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw InferenceError.network(message)
        }
        struct Response: Decodable {
            struct Message: Decodable {
                let role: String
                let content: String
            }
            let message: Message
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.message.content
    }
}

public struct EchoProvider: InferenceProvider {
    public init() {}

    public func generateReply(for env: RelayEnvelope) async throws -> String {
        let last = env.messages.last?.text ?? ""
        return "Echo: \(last)"
    }
}
