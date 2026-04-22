import Foundation
import XCTest
@testable import Noema

private final class LockedLogStore: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func append(_ message: String) {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        let snapshot = messages
        lock.unlock()
        return snapshot
    }
}

final class LoggerTests: XCTestCase {
    @MainActor
    func testSendMessageLogsAttemptBeforeLoadingBlock() async {
        let vm = ChatVM()
        vm.loading = true

        let logs = await captureLogs {
            await vm.sendMessage("hello")
        }

        assertLogOrder(
            logs,
            first: "[ChatVM][SendAttempt] hello",
            second: "[ChatVM] Blocking send: model still loading"
        )
    }

    @MainActor
    func testSendMessageLogsAttemptBeforeCrossSessionBlock() async {
        let vm = ChatVM()
        let activeSession = vm.sessions[0]
        let streamingSession = ChatVM.Session(
            title: "Other",
            messages: [.init(role: "🤖", text: "", timestamp: Date(), streaming: true)],
            date: Date(),
            datasetID: ""
        )
        vm.sessions = [activeSession, streamingSession]
        vm.activeSessionID = activeSession.id
        vm.setStreamSessionIndexForTesting(1)

        let logs = await captureLogs {
            await vm.sendMessage("hello")
        }

        assertLogOrder(
            logs,
            first: "[ChatVM][SendAttempt] hello",
            second: "[ChatVM] Blocking send: another chat is still generating"
        )
    }

    @MainActor
    func testSuccessfulSendPathLogsAttemptBeforeUserLine() async {
        let vm = ChatVM()
        vm.activeSessionID = nil

        let logs = await captureLogs {
            await vm.sendMessage("hello")
        }

        assertLogOrder(
            logs,
            first: "[ChatVM][SendAttempt] hello",
            second: "[ChatVM] USER ▶︎ hello"
        )
    }

    private func captureLogs(_ body: () async -> Void) async -> [String] {
        let store = LockedLogStore()
        let token = await logger.addObserver { message in
            store.append(message)
        }

        await body()

        await logger.removeObserver(token)
        return store.snapshot()
    }

    private func assertLogOrder(
        _ logs: [String],
        first: String,
        second: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let firstIndex = logs.firstIndex(of: first) else {
            XCTFail("Missing log: \(first)\nCaptured logs: \(logs)", file: file, line: line)
            return
        }
        guard let secondIndex = logs.firstIndex(of: second) else {
            XCTFail("Missing log: \(second)\nCaptured logs: \(logs)", file: file, line: line)
            return
        }
        XCTAssertLessThan(firstIndex, secondIndex, "Expected '\(first)' before '\(second)'. Logs: \(logs)", file: file, line: line)
    }
}
