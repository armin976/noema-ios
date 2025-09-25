import Foundation

public struct ToolResult: Sendable, Equatable {
    public let callId: String
    public let content: String

    public init(callId: String, content: String) {
        self.callId = callId
        self.content = content
    }
}

public enum ToolEvent: Sendable {
    case token(String)
    case call(ToolCall)
    case result(ToolResult)
    case done
    case error(String)
}

public protocol ToolCapableLLM: Sendable {
    func runToolLoop(
        history: [ToolChatMessage],
        tools: [String],
        timeout: TimeInterval?
    ) -> AsyncStream<ToolEvent>
}
