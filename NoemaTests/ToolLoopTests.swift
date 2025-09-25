#if canImport(Noema)
import XCTest
@testable import Noema
@testable import NoemaCore

final class ToolLoopTests: XCTestCase {
    func testHappyPathStreamsTokensAndResults() async {
        let call = ToolCall(
            id: "call-1",
            name: "demo.tool",
            arguments: "{}"
        )
        let backend = MockToolCapableLLM(events: [
            .token("Hello"),
            .call(call),
            .done
        ])

        let registry = await makeRegistry(with: TestTool(name: "demo.tool", response: "{\"ok\":true}"))
        let loop = ToolLoop(registryProvider: { registry })

        let stream = loop.run(
            for: backend,
            history: [],
            tools: ["demo.tool"],
            timeout: 1
        )

        var received: [ToolEvent] = []
        for await event in stream {
            received.append(event)
        }

        XCTAssertEqual(received.count, 4)
        guard received.count == 4 else { return }
        if case let .token(value) = received[0] {
            XCTAssertEqual(value, "Hello")
        } else {
            XCTFail("Expected token event")
        }
        if case let .call(value) = received[1] {
            XCTAssertEqual(value.id, call.id)
            XCTAssertEqual(value.function.name, call.function.name)
        } else {
            XCTFail("Expected call event")
        }
        if case let .result(result) = received[2] {
            XCTAssertEqual(result, ToolResult(callId: "call-1", content: "{\"ok\":true}"))
        } else {
            XCTFail("Expected result event")
        }
        if case .done = received[3] {
            // expected
        } else {
            XCTFail("Expected done event")
        }
    }

    func testTimeoutProducesPresentedError() async {
        let call = ToolCall(id: "call-2", name: "slow.tool", arguments: "{}")
        let backend = MockToolCapableLLM(events: [
            .call(call),
            .done
        ])

        let registry = await makeRegistry(with: SlowTool(name: "slow.tool", delay: 0.2))
        let loop = ToolLoop(registryProvider: { registry })

        let stream = loop.run(
            for: backend,
            history: [],
            tools: ["slow.tool"],
            timeout: 0.05
        )

        var errors: [String] = []
        for await event in stream {
            if case let .error(message) = event {
                errors.append(message)
            }
        }

        XCTAssertEqual(errors, ["Python timed out. Try a smaller sample or raise timeout."])
    }

    func testStructuredAppErrorMapsThroughPresenter() async {
        let call = ToolCall(id: "call-3", name: "failing.tool", arguments: "{}")
        let backend = MockToolCapableLLM(events: [
            .call(call),
            .done
        ])

        let appError = AppError(code: .pathDenied, message: "denied")
        let registry = await makeRegistry(with: ErrorTool(name: "failing.tool", error: appError))
        let loop = ToolLoop(registryProvider: { registry })

        let stream = loop.run(
            for: backend,
            history: [],
            tools: ["failing.tool"],
            timeout: 1
        )

        var errors: [String] = []
        for await event in stream {
            if case let .error(message) = event {
                errors.append(message)
            }
        }

        XCTAssertEqual(errors, ["Path access denied."])
    }
}

private func makeRegistry(with tool: Tool) async -> ToolRegistry {
    await MainActor.run {
        let registry = ToolRegistry()
        registry.register(tool)
        return registry
    }
}

private struct MockToolCapableLLM: ToolCapableLLM {
    let events: [ToolEvent]

    func runToolLoop(
        history: [ToolChatMessage],
        tools: [String],
        timeout: TimeInterval?
    ) -> AsyncStream<ToolEvent> {
        AsyncStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}

private struct TestTool: Tool {
    let name: String
    let response: String

    var description: String { "Test tool" }
    var schema: String { "{\"type\":\"object\",\"properties\":{},\"required\":[]}" }

    func call(args: Data) async throws -> Data {
        Data(response.utf8)
    }
}

private struct SlowTool: Tool {
    let name: String
    let delay: TimeInterval

    var description: String { "Slow tool" }
    var schema: String { "{\"type\":\"object\",\"properties\":{},\"required\":[]}" }

    func call(args: Data) async throws -> Data {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return Data("{}".utf8)
    }
}

private struct ErrorTool: Tool {
    let name: String
    let error: Error

    var description: String { "Error tool" }
    var schema: String { "{\"type\":\"object\",\"properties\":{},\"required\":[]}" }

    func call(args: Data) async throws -> Data {
        throw error
    }
}
#endif
