import Foundation
import NoemaCore

public struct ToolLoop {
    private let registryProvider: @Sendable () async -> ToolRegistry
    private let maxRetries: Int

    public init(
        registryProvider: @escaping @Sendable () async -> ToolRegistry = { await ToolRegistry.shared },
        maxRetries: Int = 1
    ) {
        self.registryProvider = registryProvider
        self.maxRetries = maxRetries
    }

    public static func run(
        for backend: ToolCapableLLM,
        history: [ToolChatMessage],
        tools: [String],
        timeout: TimeInterval?
    ) -> AsyncStream<ToolEvent> {
        ToolLoop().run(for: backend, history: history, tools: tools, timeout: timeout)
    }

    public func run(
        for backend: ToolCapableLLM,
        history: [ToolChatMessage],
        tools: [String],
        timeout: TimeInterval?
    ) -> AsyncStream<ToolEvent> {
        let allowedTools = Set(tools)
        let baseStream = backend.runToolLoop(history: history, tools: tools, timeout: timeout)

        return AsyncStream { continuation in
            Task {
                let registry = await registryProvider()
                var sawDone = false

                for await event in baseStream {
                    switch event {
                    case .token:
                        continuation.yield(event)
                    case .call(let call):
                        continuation.yield(.call(call))

                        guard allowedTools.contains(call.function.name) else {
                            continuation.yield(.error("Tool \(call.function.name) not permitted."))
                            continue
                        }

                        let resultEvent = await handleToolCall(call: call, registry: registry, timeout: timeout)
                        continuation.yield(resultEvent)
                    case .result, .error:
                        continuation.yield(event)
                    case .done:
                        sawDone = true
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    }
                }

                if !sawDone {
                    continuation.yield(.done)
                }
                continuation.finish()
            }
        }
    }

    private func handleToolCall(
        call: ToolCall,
        registry: ToolRegistry,
        timeout: TimeInterval?
    ) async -> ToolEvent {
        var attempt = 0
        let maxAttempts = max(1, maxRetries + 1)

        while attempt < maxAttempts {
            do {
                let result = try await performToolCall(call: call, registry: registry, timeout: timeout)
                return .result(ToolResult(callId: call.id, content: result))
            } catch {
                attempt += 1

                if attempt < maxAttempts, shouldRetry(error) {
                    continue
                }

                return .error(presentableMessage(for: error))
            }
        }

        return .error("Unknown tool execution failure.")
    }

    private func performToolCall(
        call: ToolCall,
        registry: ToolRegistry,
        timeout: TimeInterval?
    ) async throws -> String {
        try await executeWithTimeout(timeout: timeout) {
            try await registry.executeToolJSON(name: call.function.name, argumentsJSON: call.function.arguments)
        }
    }

    private func executeWithTimeout(
        timeout: TimeInterval?,
        operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        guard let timeout, timeout > 0 else {
            return try await operation()
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await sleep(for: timeout)
            }

            guard let result = try await group.next() else {
                throw ToolLoopTimeoutError()
            }

            group.cancelAll()
            return result
        }
    }

    private func sleep(for timeout: TimeInterval) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw ToolLoopTimeoutError()
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if error is ToolLoopTimeoutError { return false }
        if error is AppError { return false }
        if error is ToolError { return false }
        return true
    }

    private func presentableMessage(for error: Error) -> String {
        if let timeoutError = error as? ToolLoopTimeoutError {
            let appError = AppError(code: .pyTimeout, message: timeoutError.localizedDescription)
            return ErrorPresenter.present(appError)
        }

        if let appError = error as? AppError {
            return ErrorPresenter.present(appError)
        }

        return error.localizedDescription
    }
}

private struct ToolLoopTimeoutError: Error, LocalizedError, Sendable {
    var errorDescription: String? {
        "Tool timed out."
    }
}
