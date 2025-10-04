// ToolSpecs.swift
import Foundation

// MARK: - OpenAI-style Tool Specifications for llama.cpp server mode

public struct ToolSpec: Codable, Sendable {
    public let type = "function"
    public let function: Function
    
    public struct Function: Codable, Sendable {
        public let name: String
        public let description: String
        public let parameters: JSONSchema
    }
    
    public struct JSONSchema: Codable, Sendable {
        public let type: String
        public let properties: [String: Parameter]
        public let required: [String]
        
        public struct Parameter: Codable, Sendable {
            public let type: String
            public let description: String
            public let maximum: Int?
            public let minimum: Int?
            public let `default`: AnyCodable?
            public let `enum`: [String]?
            
            public init(type: String, description: String, maximum: Int? = nil, minimum: Int? = nil, defaultValue: AnyCodable? = nil, enumValues: [String]? = nil) {
                self.type = type
                self.description = description
                self.maximum = maximum
                self.minimum = minimum
                self.default = defaultValue
                self.enum = enumValues
            }
        }
    }
    
    public init(name: String, description: String, parameters: JSONSchema) {
        self.function = Function(name: name, description: description, parameters: parameters)
    }
}

// MARK: - Tool Call Request/Response Structures

public struct ToolChatMessage: Codable {
    public let role: String
    public let content: String?
    public let tool_calls: [ToolCall]?
    public let tool_call_id: String?
    
    public init(role: String, content: String? = nil, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = toolCalls
        self.tool_call_id = toolCallId
    }
    
    public static func system(_ content: String) -> ToolChatMessage {
        ToolChatMessage(role: "system", content: content)
    }
    
    public static func user(_ content: String) -> ToolChatMessage {
        ToolChatMessage(role: "user", content: content)
    }
    
    public static func assistant(_ content: String, toolCalls: [ToolCall]? = nil) -> ToolChatMessage {
        ToolChatMessage(role: "assistant", content: content, toolCalls: toolCalls)
    }
    
    public static func tool(result: String, callId: String) -> ToolChatMessage {
        ToolChatMessage(role: "tool", content: result, toolCallId: callId)
    }
}

public struct ToolCall: Codable {
    public let id: String
    public let type = "function"
    public let function: ToolFunction
    
    public struct ToolFunction: Codable {
        public let name: String
        public let arguments: String // JSON string
    }
    
    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.function = ToolFunction(name: name, arguments: arguments)
    }
}

public struct ChatRequest: Codable {
    public let model: String
    public let messages: [ToolChatMessage]
    public let tools: [ToolSpec]?
    public let tool_choice: String? // "auto", "none", or specific tool
    public let stream: Bool
    public let max_tokens: Int?
    public let temperature: Float?
    
    public init(model: String, messages: [ToolChatMessage], tools: [ToolSpec]? = nil, toolChoice: String? = "auto", stream: Bool = true, maxTokens: Int? = nil, temperature: Float? = nil) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.tool_choice = toolChoice
        self.stream = stream
        self.max_tokens = maxTokens
        self.temperature = temperature
    }
}

public struct ChatResponse: Codable {
    public let choices: [Choice]
    
    public struct Choice: Codable {
        public let message: ToolChatMessage
        public let finish_reason: String?
    }
}

// MARK: - In-process Tool Call Format

public struct SimpleToolCall: Codable {
    public let tool_name: String
    public let arguments: [String: AnyCodable]
    
    public init(toolName: String, arguments: [String: AnyCodable]) {
        self.tool_name = toolName
        self.arguments = arguments
    }
}

// MARK: - Tool Validation

public enum ToolError: Error {
    case unknownTool(String)
    case invalidArguments(String)
    case executionFailed(String)
    case tooManyTurns
    case parseError(String)
}
