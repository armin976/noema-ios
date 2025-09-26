import Foundation

public enum ToolBridge {
    public static func runIfCapable(
        _ backend: Any,
        history: [ToolChatMessage],
        tools: [String],
        timeout: TimeInterval?
    ) -> AsyncStream<ToolEvent> {
        guard let toolBackend = backend as? ToolCapableLLM else {
            return AsyncStream { continuation in
                continuation.yield(.done)
                continuation.finish()
            }
        }

        return ToolLoop.run(for: toolBackend, history: history, tools: tools, timeout: timeout)
    }
}
