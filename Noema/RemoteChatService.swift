import Foundation

actor RemoteChatService {
    struct RequestOptions {
        var stops: [String] = []
        var temperature: Double?
        var includeTools: Bool = false
    }

    private enum EndpointKind { case chat, completion }

    enum RemoteChatError: Error, LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case httpError(Int, String)
        case missingModelIdentifier

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "Could not build the remote chat endpoint URL."
            case .invalidResponse:
                return "Remote server returned an unexpected response."
            case .httpError(let code, let body):
                if body.isEmpty { return "Remote server responded with status code \(code)." }
                return "Remote server responded with status code \(code): \(body)"
            case .missingModelIdentifier:
                return "No remote model identifier provided."
            }
        }
    }

    private struct ToolCallAccumulator {
        var id: String?
        var name: String?
        var arguments: String = ""
    }

    private struct ToolCallChunk: Decodable {
        struct FunctionFragment: Decodable {
            let name: String?
            let arguments: String?

            enum CodingKeys: String, CodingKey {
                case name
                case arguments
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decodeIfPresent(String.self, forKey: .name)
                if let string = try container.decodeIfPresent(String.self, forKey: .arguments) {
                    arguments = string
                } else if let map = try? container.decode([String: AnyCodable].self, forKey: .arguments) {
                    let jsonObject = map.mapValues { $0.value }
                    if JSONSerialization.isValidJSONObject(jsonObject),
                       let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
                       let jsonString = String(data: data, encoding: .utf8) {
                        arguments = jsonString
                    } else {
                        arguments = nil
                    }
                } else if let any = try? container.decode(AnyCodable.self, forKey: .arguments) {
                    let value = any.value
                    if let json = value as? [Any], JSONSerialization.isValidJSONObject(json),
                       let data = try? JSONSerialization.data(withJSONObject: json, options: []),
                       let jsonString = String(data: data, encoding: .utf8) {
                        arguments = jsonString
                    } else if let json = value as? [String: Any], JSONSerialization.isValidJSONObject(json),
                              let data = try? JSONSerialization.data(withJSONObject: json, options: []),
                              let jsonString = String(data: data, encoding: .utf8) {
                        arguments = jsonString
                    } else {
                        arguments = nil
                    }
                } else {
                    arguments = nil
                }
            }
        }

        let index: Int?
        let id: String?
        let type: String?
        let function: FunctionFragment?

        enum CodingKeys: String, CodingKey {
            case index
            case id
            case type
            case function
        }
    }

    private struct FunctionCallChunk: Decodable {
        let name: String?
        let arguments: String?

        enum CodingKeys: String, CodingKey {
            case name
            case arguments
        }
    }

    private struct ChatChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let role: String?
                let content: String?
                let toolCalls: [ToolCallChunk]?
                let functionCall: FunctionCallChunk?
            }

            struct Message: Decodable {
                let role: String?
                let content: String?
                let toolCalls: [ToolCallChunk]?
                let functionCall: FunctionCallChunk?
            }

            let index: Int?
            let delta: Delta?
            let message: Message?
            let text: String?
            let completion: String?
            let finishReason: String?
        }

        let choices: [Choice]
    }

    private struct OllamaChatChunk: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
            let toolCalls: [ToolCallChunk]?
        }

        let model: String?
        let createdAt: String?
        let message: Message?
        let done: Bool?
        let doneReason: String?
    }

    private var backend: RemoteBackend
    private var modelID: String
    private var toolSpecs: [ToolSpec]
    private var options = RequestOptions()
    private var cancellationHandler: (() -> Void)?
    private let decoder: JSONDecoder
    private var bufferedToolTokens: [String] = []

    init(backend: RemoteBackend, modelID: String, toolSpecs: [ToolSpec]) {
        self.backend = backend
        self.modelID = modelID
        self.toolSpecs = toolSpecs
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func updateBackend(_ backend: RemoteBackend) {
        self.backend = backend
    }

    func updateModelID(_ id: String) {
        self.modelID = id
    }

    func updateToolSpecs(_ specs: [ToolSpec]) {
        self.toolSpecs = specs
    }

    func updateOptions(stops: [String], temperature: Double?, includeTools: Bool) {
        options = RequestOptions(stops: stops, temperature: temperature, includeTools: includeTools)
    }

    func cancelActiveStream() {
        cancellationHandler?()
        cancellationHandler = nil
    }

    func stream(for input: LLMInput) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.performStream(for: input, continuation: continuation)
                await self.clearCancellationHandler()
            }
            Task { await self.setCancellationHandler { task.cancel() } }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.clearCancellationHandler() }
            }
        }
    }

    private func setCancellationHandler(_ handler: @escaping () -> Void) {
        cancellationHandler = handler
    }

    private func clearCancellationHandler() {
        cancellationHandler = nil
    }

    private func currentEndpointKind() -> EndpointKind {
        let rawPath: String
        if let url = backend.chatEndpointURL {
            rawPath = url.path.lowercased()
        } else {
            rawPath = backend.normalizedChatPath.lowercased()
        }
        if rawPath.contains("/chat/") || rawPath.hasSuffix("/chat") {
            return .chat
        }
        return .completion
    }

    private func performStream(for input: LLMInput, continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        bufferedToolTokens.removeAll(keepingCapacity: false)

        do {
            let prompt = input.prompt
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continuation.finish()
                return
            }

            if backend.endpointType == .ollama {
                try await performOllamaStream(prompt: prompt, continuation: continuation)
                return
            }

            let kind = currentEndpointKind()
            let request = try buildRequest(prompt: prompt, kind: kind)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw RemoteChatError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                var buffer = Data()
                var iterator = bytes.makeAsyncIterator()
                while let byte = try await iterator.next() {
                    buffer.append(byte)
                    if buffer.count >= 4096 { break }
                }
                let body = String(data: buffer, encoding: .utf8) ?? ""
                throw RemoteChatError.httpError(http.statusCode, body)
            }

            let isChat = kind == .chat
            var accumulators: [String: ToolCallAccumulator] = [:]
            var lastEmittedToolJSON: [String: String] = [:]
            var responseItemIndex: [String: String] = [:]
            var responseOutputActiveKey: [Int: String] = [:]
            var nextResponseAccumulatorID = 0
            var sawToolCallFinish = false

            func registerItemID(_ id: String?, key: String) {
                guard let id, !id.isEmpty else { return }
                responseItemIndex[id] = key
            }

            func emitToolCallUpdate(for key: String, force: Bool = false) {
                guard let accumulator = accumulators[key],
                      let jsonString = makeToolCallJSON(from: accumulator) else { return }
                if !force, lastEmittedToolJSON[key] == jsonString { return }
                lastEmittedToolJSON[key] = jsonString
                logToolCallPayload(jsonString)
                let token = "TOOL_CALL: \(jsonString)"
                let result = continuation.yield(token)
                switch result {
                case .enqueued:
                    break
                case .dropped, .terminated:
                    bufferedToolTokens.append(token)
                @unknown default:
                    bufferedToolTokens.append(token)
                }
            }

            func callKey(forIndex index: Int) -> String {
                "idx:\(index)"
            }

            func newResponseAccumulatorKey() -> String {
                defer { nextResponseAccumulatorID += 1 }
                return "response:\(nextResponseAccumulatorID)"
            }

            func updateAccumulator(_ call: ToolCallChunk, fallbackIndex: Int, replaceArguments: Bool) {
                let idx = call.index ?? fallbackIndex
                let key = callKey(forIndex: idx)
                var accumulator = accumulators[key, default: ToolCallAccumulator()]
                registerItemID(call.id, key: key)
                if let id = call.id, !id.isEmpty { accumulator.id = id }
                if let name = call.function?.name, !name.isEmpty { accumulator.name = name }
                if let fragment = call.function?.arguments, !fragment.isEmpty {
                    if replaceArguments {
                        accumulator.arguments = fragment
                    } else {
                        accumulator.arguments.append(fragment)
                    }
                }
                accumulators[key] = accumulator
                emitToolCallUpdate(for: key)
            }

            func updateFunctionAccumulator(_ call: FunctionCallChunk, replaceArguments: Bool) {
                let key = callKey(forIndex: 0)
                var accumulator = accumulators[key, default: ToolCallAccumulator()]
                if let name = call.name, !name.isEmpty { accumulator.name = name }
                if let fragment = call.arguments, !fragment.isEmpty {
                    if replaceArguments {
                        accumulator.arguments = fragment
                    } else {
                        accumulator.arguments.append(fragment)
                    }
                }
                accumulators[key] = accumulator
                emitToolCallUpdate(for: key)
            }

            func intFromAny(_ value: Any?) -> Int? {
                if let int = value as? Int { return int }
                if let double = value as? Double { return Int(double) }
                if let string = value as? String, let int = Int(string) { return int }
                return nil
            }

            func stringFromJSONValue(_ value: Any) -> String? {
                if let string = value as? String { return string }
                if JSONSerialization.isValidJSONObject(value),
                   let data = try? JSONSerialization.data(withJSONObject: value, options: []),
                   let string = String(data: data, encoding: .utf8) {
                    return string
                }
                return nil
            }

            func stringFromDeltaValue(_ value: Any) -> String? {
                if let string = value as? String { return string }
                if let dict = value as? [String: Any] {
                    if let text = dict["text"] as? String { return text }
                    if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
                       let string = String(data: data, encoding: .utf8) {
                        return string
                    }
                }
                return nil
            }

            func handleResponseEvent(_ event: [String: Any]) -> Error? {
                guard let type = event["type"] as? String else { return nil }
                switch type {
                case "response.output_text.delta":
                    if let deltaValue = event["delta"],
                       let text = stringFromDeltaValue(deltaValue),
                       !text.isEmpty {
                        continuation.yield(text)
                    }
                case "response.output_item.added":
                    guard let item = event["item"] as? [String: Any],
                          let itemType = item["type"] as? String else { break }
                    let defaultIndex = intFromAny(event["output_index"]) ?? 0
                    if itemType == "function_call" {
                        let existingKey: String? = {
                            if let id = item["id"] as? String, let key = responseItemIndex[id] { return key }
                            if let callID = item["call_id"] as? String, let key = responseItemIndex[callID] { return key }
                            return nil
                        }()
                        let key = existingKey ?? newResponseAccumulatorKey()
                        registerItemID(item["id"] as? String, key: key)
                        registerItemID(item["call_id"] as? String, key: key)
                        responseOutputActiveKey[defaultIndex] = key
                        var accumulator = accumulators[key, default: ToolCallAccumulator()]
                        if let id = item["id"] as? String, !id.isEmpty {
                            accumulator.id = id
                        } else if let callID = item["call_id"] as? String, !callID.isEmpty {
                            accumulator.id = callID
                        }
                        if let name = item["name"] as? String, !name.isEmpty { accumulator.name = name }
                        if let argumentsValue = item["arguments"],
                           let arguments = stringFromJSONValue(argumentsValue) {
                            accumulator.arguments = arguments
                        }
                        accumulators[key] = accumulator
                        emitToolCallUpdate(for: key, force: true)
                    }
                case "response.function_call_arguments.delta":
                    let defaultIndex = intFromAny(event["output_index"]) ?? 0
                    let key: String = {
                        if let itemID = event["item_id"] as? String,
                           let mapped = responseItemIndex[itemID] {
                            return mapped
                        }
                        if let mapped = responseOutputActiveKey[defaultIndex] {
                            return mapped
                        }
                        let newKey = newResponseAccumulatorKey()
                        responseOutputActiveKey[defaultIndex] = newKey
                        return newKey
                    }()
                    registerItemID(event["item_id"] as? String, key: key)
                    var accumulator = accumulators[key, default: ToolCallAccumulator()]
                    if let itemID = event["item_id"] as? String, !itemID.isEmpty,
                       accumulator.id == nil {
                        accumulator.id = itemID
                    }
                    if let deltaValue = event["delta"],
                       let fragment = stringFromDeltaValue(deltaValue),
                       !fragment.isEmpty {
                        accumulator.arguments.append(fragment)
                    }
                    accumulators[key] = accumulator
                    emitToolCallUpdate(for: key)
                case "response.function_call_arguments.done":
                    let defaultIndex = intFromAny(event["output_index"]) ?? 0
                    let key: String = {
                        if let itemID = event["item_id"] as? String,
                           let mapped = responseItemIndex[itemID] {
                            return mapped
                        }
                        if let mapped = responseOutputActiveKey[defaultIndex] {
                            return mapped
                        }
                        let newKey = newResponseAccumulatorKey()
                        responseOutputActiveKey[defaultIndex] = newKey
                        return newKey
                    }()
                    registerItemID(event["item_id"] as? String, key: key)
                    var accumulator = accumulators[key, default: ToolCallAccumulator()]
                    if let itemID = event["item_id"] as? String, !itemID.isEmpty,
                       accumulator.id == nil {
                        accumulator.id = itemID
                    }
                    if let argumentsValue = event["arguments"],
                       let arguments = stringFromJSONValue(argumentsValue) {
                        accumulator.arguments = arguments
                    }
                    accumulators[key] = accumulator
                    emitToolCallUpdate(for: key, force: true)
                    sawToolCallFinish = true
                case "response.completed":
                    sawToolCallFinish = sawToolCallFinish || !accumulators.isEmpty
                case "response.error":
                    if let errorDict = event["error"] as? [String: Any] {
                        let message = errorDict["message"] as? String ?? "Remote server error"
                        let codeValue = errorDict["code"]
                        let code: Int = {
                            if let int = codeValue as? Int { return int }
                            if let string = codeValue as? String, let parsed = Int(string) { return parsed }
                            return -1
                        }()
                        return RemoteChatError.httpError(code, message)
                    }
                default:
                    break
                }
                return nil
            }

            for try await rawLine in bytes.lines {
                try Task.checkCancellation()
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8) else { continue }
                if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = jsonObject["type"] as? String,
                   type.hasPrefix("response.") {
                    if let error = handleResponseEvent(jsonObject) {
                        throw error
                    }
                    continue
                }
                let chunk: ChatChunk
                do {
                    chunk = try decoder.decode(ChatChunk.self, from: data)
                } catch {
                    continue
                }

                for choice in chunk.choices {
                    if let delta = choice.delta {
                        if let content = delta.content, !content.isEmpty {
                            continuation.yield(content)
                        }
                        if isChat, let toolCalls = delta.toolCalls, !toolCalls.isEmpty {
                            for call in toolCalls {
                                let fallback = call.index ?? 0
                                updateAccumulator(call, fallbackIndex: fallback, replaceArguments: false)
                            }
                        }
                        if isChat, let fnCall = delta.functionCall {
                            updateFunctionAccumulator(fnCall, replaceArguments: false)
                            sawToolCallFinish = true
                        }
                    }
                    if isChat, let messageToolCalls = choice.message?.toolCalls, !messageToolCalls.isEmpty {
                        for (relativeIndex, call) in messageToolCalls.enumerated() {
                            updateAccumulator(call, fallbackIndex: call.index ?? relativeIndex, replaceArguments: true)
                        }
                        sawToolCallFinish = true
                    }
                    if isChat, let messageFnCall = choice.message?.functionCall {
                        updateFunctionAccumulator(messageFnCall, replaceArguments: true)
                        sawToolCallFinish = true
                    }
                    if !isChat {
                        if let text = choice.text, !text.isEmpty {
                            continuation.yield(text)
                        }
                        if let completion = choice.completion, !completion.isEmpty {
                            continuation.yield(completion)
                        }
                        if let messageContent = choice.message?.content, !messageContent.isEmpty {
                            continuation.yield(messageContent)
                        }
                    }
                    if isChat, let reason = choice.finishReason {
                        if reason == "tool_calls" || reason == "function_call" {
                            sawToolCallFinish = true
                        }
                    }
                }
            }

            if isChat && (sawToolCallFinish || !accumulators.isEmpty) {
                for (key, _) in accumulators.sorted(by: { $0.key < $1.key }) {
                    emitToolCallUpdate(for: key, force: true)
                }
            }

            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func performOllamaStream(prompt: String, continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        bufferedToolTokens.removeAll(keepingCapacity: false)

        let request = try buildOllamaRequest(prompt: prompt)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw RemoteChatError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            var buffer = Data()
            var iterator = bytes.makeAsyncIterator()
            while let byte = try await iterator.next() {
                buffer.append(byte)
                if buffer.count >= 4096 { break }
            }
            let body = String(data: buffer, encoding: .utf8) ?? ""
            throw RemoteChatError.httpError(http.statusCode, body)
        }

        var accumulators: [Int: ToolCallAccumulator] = [:]
        var lastEmittedToolJSON: [Int: String] = [:]

        func emitToolCallUpdate(for index: Int, force: Bool = false) {
            guard let accumulator = accumulators[index],
                  let jsonString = makeToolCallJSON(from: accumulator) else { return }
            if !force, lastEmittedToolJSON[index] == jsonString { return }
            lastEmittedToolJSON[index] = jsonString
            logToolCallPayload(jsonString)
            let token = "TOOL_CALL: \(jsonString)"
            let result = continuation.yield(token)
            switch result {
            case .enqueued:
                break
            case .dropped, .terminated:
                bufferedToolTokens.append(token)
            @unknown default:
                bufferedToolTokens.append(token)
            }
        }

        func updateAccumulator(_ call: ToolCallChunk, fallbackIndex: Int, replaceArguments: Bool) {
            let idx = call.index ?? fallbackIndex
            var accumulator = accumulators[idx, default: ToolCallAccumulator()]
            if let id = call.id, !id.isEmpty { accumulator.id = id }
            if let name = call.function?.name, !name.isEmpty { accumulator.name = name }
            if let fragment = call.function?.arguments, !fragment.isEmpty {
                if replaceArguments {
                    accumulator.arguments = fragment
                } else {
                    accumulator.arguments.append(fragment)
                }
            }
            accumulators[idx] = accumulator
            emitToolCallUpdate(for: idx, force: replaceArguments)
        }

        for try await rawLine in bytes.lines {
            try Task.checkCancellation()
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }
            let chunk: OllamaChatChunk
            do {
                chunk = try decoder.decode(OllamaChatChunk.self, from: data)
            } catch {
                continue
            }

            if let content = chunk.message?.content, !content.isEmpty {
                continuation.yield(content)
            }

            if let toolCalls = chunk.message?.toolCalls, !toolCalls.isEmpty {
                for (index, call) in toolCalls.enumerated() {
                    updateAccumulator(call, fallbackIndex: call.index ?? index, replaceArguments: true)
                }
            }

            if chunk.done == true {
                break
            }
        }

        if !accumulators.isEmpty {
            for (index, _) in accumulators.sorted(by: { $0.key < $1.key }) {
                emitToolCallUpdate(for: index, force: true)
            }
        }

        continuation.finish()
    }

    private func buildRequest(prompt: String, kind: EndpointKind) throws -> URLRequest {
        guard let url = backend.chatEndpointURL else {
            throw RemoteChatError.invalidEndpoint
        }

        let trimmedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelValue: String = {
            if !trimmedModel.isEmpty { return trimmedModel }
            if let fallback = backend.customModelIDs.first { return fallback }
            return trimmedModel
        }()
        guard !modelValue.isEmpty else {
            throw RemoteChatError.missingModelIdentifier
        }

        let allowTools = options.includeTools && kind == .chat && !toolSpecs.isEmpty

        var body: [String: Any] = [
            "model": modelValue,
            "stream": true
        ]

        switch kind {
        case .chat:
            body["messages"] = [["role": "user", "content": prompt]]
            if allowTools {
                body["tools"] = try toolsPayload(from: toolSpecs)
                body["tool_choice"] = "auto"
            }
        case .completion:
            body["prompt"] = prompt
        }
        if !options.stops.isEmpty {
            body["stop"] = options.stops
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }

        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = backend.authHeader, !auth.isEmpty {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func buildOllamaRequest(prompt: String) throws -> URLRequest {
        guard let url = backend.chatEndpointURL else {
            throw RemoteChatError.invalidEndpoint
        }

        let trimmedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw RemoteChatError.missingModelIdentifier
        }

        var body: [String: Any] = [
            "model": trimmedModel,
            "stream": true,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "keep_alive": "5m"
        ]

        var optionsPayload: [String: Any] = [:]
        if !options.stops.isEmpty {
            optionsPayload["stop"] = options.stops
        }
        if let temperature = options.temperature {
            optionsPayload["temperature"] = temperature
        }
        if !optionsPayload.isEmpty {
            body["options"] = optionsPayload
        }

        if options.includeTools && !toolSpecs.isEmpty {
            body["tools"] = try toolsPayload(from: toolSpecs)
        }

        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = backend.authHeader, !auth.isEmpty {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func drainBufferedToolTokens() -> [String] {
        let tokens = bufferedToolTokens
        bufferedToolTokens.removeAll(keepingCapacity: false)
        return tokens
    }

    private func logToolCallPayload(_ jsonString: String) {
        let backendName = backend.name
        let trimmedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackModel = backend.customModelIDs.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelLabel: String
        if !trimmedModel.isEmpty {
            modelLabel = trimmedModel
        } else if let fallbackModel, !fallbackModel.isEmpty {
            modelLabel = fallbackModel
        } else {
            modelLabel = "(unspecified model)"
        }
        Task {
            await logger.logFull("[Remote][Tool][\(backendName)][\(modelLabel)] Endpoint requested tool call: \(jsonString)")
        }
    }

    private func toolsPayload(from specs: [ToolSpec]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(specs)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    private func makeToolCallJSON(from accumulator: ToolCallAccumulator) -> String? {
        guard let name = accumulator.name, !name.isEmpty else { return nil }
        let argumentsString = accumulator.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        var argumentsObject: Any = [:]
        if let data = argumentsString.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            argumentsObject = obj
        } else if !argumentsString.isEmpty {
            argumentsObject = ["raw": argumentsString]
        }

        var payload: [String: Any] = [
            "tool": name,
            "tool_name": name,
            "args": argumentsObject,
            "arguments": argumentsObject
        ]

        if let id = accumulator.id, !id.isEmpty {
            payload["id"] = id
            payload["tool_call_id"] = id
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        return jsonString
    }
}
