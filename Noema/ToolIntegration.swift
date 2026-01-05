// ToolIntegration.swift
import Foundation

// MARK: - Integration with Existing Noema Architecture

// Enhanced BackendRouter with tool support
final class ToolEnabledBackendRouter {
    private var backend: (any InferenceBackend)?
    private var toolBackend: ToolEnabledBackend?
    
    func open(model: InstalledModel) async throws -> ToolEnabledBackend {
        // Unload existing backend
        if let current = backend {
            var c = current
            c.unload()
        }
        
        // Initialize tool system
        await ToolRegistrar.shared.initializeTools()
        
        // Create appropriate tool-enabled backend
        if LlamaBackend.supported.contains(model.format) {
            var b = EnhancedLlamaBackend()
            try await b.load(model)
            let toolBackend = ToolEnabledBackend.llama(b)
            self.toolBackend = toolBackend
            return toolBackend
        }
        
        if MLXBackend.supported.contains(model.format) {
            if !DeviceGPUInfo.supportsGPUOffload {
                throw NSError(
                    domain: "Noema",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "MLX models require A13+ GPU on this device. For best performance, use SLM (Leap) models; otherwise use GGUF."]
                )
            }
            var b = EnhancedMLXBackend()
            try await b.load(model)
            let toolBackend = ToolEnabledBackend.mlx(b)
            self.toolBackend = toolBackend
            return toolBackend
        }
        
        #if canImport(LeapSDK)
        if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
            if LeapBackend.supported.contains(model.format) {
                var b = LeapBackend()
                try await b.load(model)
                // For now, wrap Leap backend without tool support
                let toolBackend = ToolEnabledBackend.leap(b)
                self.toolBackend = toolBackend
                return toolBackend
            }
        }
        #endif
        
        throw NSError(domain: "Noema", code: -1, userInfo: [NSLocalizedDescriptionKey: "Requested backend unavailable"])
    }
    
    func getCurrentToolBackend() -> ToolEnabledBackend? {
        return toolBackend
    }
}
// Wrapper for different backend types with tool support
enum ToolEnabledBackend {
    case llama(EnhancedLlamaBackend)
    case mlx(EnhancedMLXBackend)
#if canImport(LeapSDK)
    case leap(LeapBackend) // No tool support yet
#endif

    func generate(streaming request: GenerateRequest) -> AsyncThrowingStream<TokenEvent, Error> {
        switch self {
        case .llama(let backend):
            return backend.generate(streaming: request)
        case .mlx(let backend):
            return backend.generate(streaming: request)
#if canImport(LeapSDK)
        case .leap(let backend):
            return backend.generate(streaming: request)
#endif
        }
    }

    func runToolLoop(messages: inout [ToolChatMessage]) async throws -> String {
        switch self {
        case .llama(let backend):
            return try await backend.runToolLoop(messages: &messages)
        case .mlx(let backend):
            return try await backend.runToolLoop(messages: &messages)
#if canImport(LeapSDK)
        case .leap:
            throw ToolError.executionFailed("Tool calling not supported for Leap backend")
#endif
        }
    }

    var supportsTools: Bool {
        switch self {
        case .llama, .mlx:
            return true
#if canImport(LeapSDK)
        case .leap:
            return false
#endif
        }
    }
}

// MARK: - ChatVM Integration

private typealias APIToolCall = ToolCall

#if os(iOS) || os(visionOS)
extension ChatVM {

    // Enhanced message structure for tool calls
    struct EnhancedMessage {
        let id = UUID()
        let role: String
        let content: String?
        let toolCalls: [ChatVM.Msg.ToolCall]?
        let timestamp = Date()
        
        var chatMessage: ToolChatMessage {
            // Convert ChatVM.Msg.ToolCall (ChatVM.ToolCall) to global ToolSpecs.ToolCall
            var mapped: [APIToolCall]? = nil
            if let tc = toolCalls {
                mapped = tc.map { c in
                    // c is ChatVM.Msg.ToolCall
                    let id = c.id.uuidString
                    let name = c.toolName
                    // Serialize requestParams ([String: AnyCodable]) to JSON string
                    var argsJSON = "{}"
                    if let data = try? JSONEncoder().encode(c.requestParams), let s = String(data: data, encoding: .utf8) {
                        argsJSON = s
                    }
                    return APIToolCall(id: id, name: name, arguments: argsJSON)
                }
            }

            return ToolChatMessage(
                role: role,
                content: content,
                toolCalls: mapped
            )
        }
        
        static func user(_ content: String) -> EnhancedMessage {
            EnhancedMessage(role: "user", content: content, toolCalls: nil)
        }
        
        static func assistant(_ content: String, toolCalls: [ChatVM.Msg.ToolCall]? = nil) -> EnhancedMessage {
            EnhancedMessage(role: "assistant", content: content, toolCalls: toolCalls)
        }
        
        static func system(_ content: String) -> EnhancedMessage {
            EnhancedMessage(role: "system", content: content, toolCalls: nil)
        }
        
        static func tool(result: String, callId: String) -> EnhancedMessage {
            let toolMessage = ToolChatMessage.tool(result: result, callId: callId)
            return EnhancedMessage(role: "tool", content: result, toolCalls: nil)
        }
    }
    
    // Method to send a message with tool support
    func sendMessageWithTools(_ content: String, useTools: Bool = true) async {
        // For now, just log the request since we need to integrate with actual ChatVM structure
        await logger.log("[ChatVM] Tool-enabled message request: \(content)")
        
        // This would need to be integrated with the actual ChatVM implementation
        // which would require access to the actual model selection and message handling
        await logger.log("[ChatVM] Tool support integration pending")
        
        // Placeholder implementation
        do {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await logger.log("[ChatVM] Tool message processing completed")
        } catch {
            await logger.log("[ChatVM] Tool message processing failed: \(error.localizedDescription)")
        }
    }
}
#endif

// MARK: - Usage Example

struct ToolUsageExample {
    
    static func demonstrateToolUsage() async throws {
        // Initialize the tool system
        await ToolRegistrar.shared.initializeTools()
        
        // Check available tools
        let availableTools = await ToolManager.shared.availableTools
        print("Available tools: \(availableTools)")
        
        // Example: Manual tool execution
        if availableTools.contains("noema.web.retrieve") {
            let result = try await ToolRegistry.shared.executetool(
                name: "noema.web.retrieve",
                arguments: [
                    "query": "latest news about AI",
                    "count": 3
                ]
            )
            print("Web search result: \(result)")
        }
        
        // Example: Tool loop usage (would require actual backend)
        /*
        let messages = [
            ToolChatMessage.system("You are a helpful assistant with access to tools."),
            ToolChatMessage.user("What's the weather like in San Francisco?")
        ]
        
        let backend = // ... initialize backend
        let response = try await backend.runToolLoop(messages: &messages)
        print("Tool loop response: \(response)")
        */
    }
}

// MARK: - Environment Configuration

struct ToolEnvironment {
    
    static func configureForServer() {
        // Note: Environment variables cannot be set at runtime in iOS/macOS apps
        // These would need to be set at launch time or via Info.plist
        print("To use server mode, set LLAMA_SERVER_URL=http://localhost:8080 at launch")
        print("To configure SearXNG search, add SearXNGURL to Secrets.plist or set SEARXNG_URL at launch")
    }
    
    static func configureForLocal() {
        // Local mode is the default when no server URL is set
        print("Using local mode (default when LLAMA_SERVER_URL is not set)")
    }
    
    static func printConfiguration() async {
        print("Tool System Configuration:")
        print("- LLAMA_SERVER_URL: \(ProcessInfo.processInfo.environment["LLAMA_SERVER_URL"] ?? "not set (using local)")")
        let endpoint = AppSecrets.searxngSearchURL
        print("- SearXNG search endpoint: \(endpoint.absoluteString)")
        print("- Available tools: \(await ToolManager.shared.availableTools)")
    }
}
