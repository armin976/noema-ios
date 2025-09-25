import XCTest
@testable import Noema

@MainActor
final class PythonRunnerStreamingTests: XCTestCase {
    func testStreamReceivesEventsInOrder() async throws {
        let runner = PythonRunner()
        let runID = UUID()
        let expectation = expectation(description: "events")
        var received: [PythonLogEvent] = []

        let stream = AsyncStream<PythonLogEvent> { continuation in
            runner.registerStreamForTesting(runID: runID, continuation: continuation)
        }

        Task {
            for await event in stream {
                received.append(event)
                if received.count == 3 {
                    expectation.fulfill()
                }
            }
        }

        let base = Date()
        runner.processScriptMessage(["type": "stdout", "data": "a", "ts": base.timeIntervalSince1970 * 1000])
        runner.processScriptMessage(["type": "stderr", "data": "b", "ts": base.addingTimeInterval(0.1).timeIntervalSince1970 * 1000])
        runner.processScriptMessage(["type": "status", "data": "finished", "ts": base.addingTimeInterval(0.2).timeIntervalSince1970 * 1000])

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(received.map { $0.kind }, [.stdout, .stderr, .status])
        XCTAssertEqual(received.last?.line, "finished")
    }

    func testRunWithStreamingEmitsStdout() async throws {
        let runner = PythonRunner()
        try await runner.start()
        let (runID, stream) = runner.runWithStreaming(code: "print('a')\nprint('b')", files: [], timeoutMs: 5_000)
        var stdoutLines: [String] = []
        let completed = expectation(description: "stream finished")

        Task {
            for await event in stream {
                if event.kind == .stdout {
                    stdoutLines.append(event.line)
                }
            }
            completed.fulfill()
        }

        let result = try await runner.awaitResult(for: runID)
        await fulfillment(of: [completed], timeout: 5.0)
        XCTAssertTrue(result.stdout.contains("a"))
        XCTAssertGreaterThanOrEqual(stdoutLines.count, 2)
        runner.teardown()
    }

    func testConsoleMetadataTrim() {
        let cell = Cell(kind: .code)
        let store = NotebookStore(notebook: Notebook(cells: [cell]))
        let lines = (0..<350).map { index in
            ConsolePersistedLine(kind: .stdout, text: "\(index)", timestamp: Date())
        }
        guard let first = store.notebook.cells.first else {
            return XCTFail("Expected cell")
        }
        store.updateConsoleHistory(for: first, history: lines, maxHistory: 300)
        guard let updated = store.notebook.cells.first?.metadata?.lastConsole else {
            return XCTFail("Expected metadata")
        }
        XCTAssertEqual(updated.count, 300)
        XCTAssertEqual(updated.first?.text, "50")
    }
}
