#if os(macOS)
import XCTest
@testable import Noema

final class RelayManagementViewModelTests: XCTestCase {
    @MainActor
    func testStartTransitionsToRunningAsSoonAsHTTPServerIsReady() async {
        let server = RelayHTTPServerStub(state: .init(isRunning: true,
                                                      bindHost: "0.0.0.0",
                                                      port: 12345,
                                                      reachableLANAddress: "http://10.0.0.57:12345"))
        let cloudKit = CloudKitTracker()
        let viewModel = makeViewModel(servers: [server], cloudKit: cloudKit) { _, _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return .empty
        }

        viewModel.start()
        defer { viewModel.stop() }

        await waitUntil {
            viewModel.serverState == .running
            && viewModel.lanReachableAddress == "http://10.0.0.57:12345"
            && !viewModel.isLANServerStarting
        }

        XCTAssertEqual(viewModel.lanReachableAddress, "http://10.0.0.57:12345")
        XCTAssertEqual(viewModel.statusMessage, "Listening for conversations… Checking sources…")
    }

    @MainActor
    func testStopCancelsInFlightStartupAndPreventsLateRunningTransition() async {
        let gate = AsyncGate()
        let server = RelayHTTPServerStub(state: .init(isRunning: true,
                                                      bindHost: "0.0.0.0",
                                                      port: 12345,
                                                      reachableLANAddress: "http://10.0.0.57:12345"),
                                         startGate: gate)
        let viewModel = makeViewModel(servers: [server]) { _, _ in
            .empty
        }

        viewModel.start()
        await waitUntilAsync { await server.startCalls() == 1 }

        viewModel.stop()
        await gate.open()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.serverState, .stopped)
        XCTAssertNil(viewModel.lanReachableAddress)
        XCTAssertFalse(viewModel.isLANServerStarting)
    }

    @MainActor
    func testStopThenStartIgnoresCompletionsFromPreviousRun() async {
        let firstGate = AsyncGate()
        let firstServer = RelayHTTPServerStub(state: .init(isRunning: true,
                                                           bindHost: "0.0.0.0",
                                                           port: 12345,
                                                           reachableLANAddress: "http://10.0.0.57:12345"),
                                              startGate: firstGate)
        let secondServer = RelayHTTPServerStub(state: .init(isRunning: true,
                                                            bindHost: "0.0.0.0",
                                                            port: 12345,
                                                            reachableLANAddress: "http://10.0.0.91:12345"))
        let viewModel = makeViewModel(servers: [firstServer, secondServer]) { _, _ in
            .empty
        }

        viewModel.start()
        await waitUntilAsync { await firstServer.startCalls() == 1 }

        viewModel.stop()
        viewModel.start()
        await waitUntil {
            viewModel.serverState == .running
            && viewModel.lanReachableAddress == "http://10.0.0.91:12345"
        }

        await firstGate.open()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.serverState, .running)
        XCTAssertEqual(viewModel.lanReachableAddress, "http://10.0.0.91:12345")

        viewModel.stop()
    }

    @MainActor
    func testWarmupOfflineBackendsUpdateStatusWithoutLeavingRunning() async {
        let server = RelayHTTPServerStub(state: .init(isRunning: true,
                                                      bindHost: "0.0.0.0",
                                                      port: 12345,
                                                      reachableLANAddress: "http://10.0.0.57:12345"))
        let viewModel = makeViewModel(servers: [server]) { _, _ in
            RelayWarmupHealth(names: ["LM Studio"], offlineModelIDs: [])
        }

        viewModel.start()
        defer { viewModel.stop() }

        await waitUntil {
            viewModel.serverState == .running
            && viewModel.statusMessage == "Listening for conversations… Offline: LM Studio"
        }

        XCTAssertEqual(viewModel.serverState, .running)
    }

    @MainActor
    func testWarmupFailureLeavesRelayRunning() async {
        struct TestError: Error {}

        let server = RelayHTTPServerStub(state: .init(isRunning: true,
                                                      bindHost: "0.0.0.0",
                                                      port: 12345,
                                                      reachableLANAddress: "http://10.0.0.57:12345"))
        let viewModel = makeViewModel(servers: [server]) { _, _ in
            throw TestError()
        }

        viewModel.start()
        defer { viewModel.stop() }

        await waitUntil {
            viewModel.serverState == .running
            && viewModel.statusMessage == "Listening for conversations…"
        }

        XCTAssertEqual(viewModel.serverState, .running)
    }

    @MainActor
    func testStopInvokesCloudKitStopAndClearsPublishedState() async {
        let server = RelayHTTPServerStub(state: .init(isRunning: true,
                                                      bindHost: "0.0.0.0",
                                                      port: 12345,
                                                      reachableLANAddress: "http://10.0.0.57:12345"))
        let cloudKit = CloudKitTracker()
        let viewModel = makeViewModel(servers: [server], cloudKit: cloudKit) { _, _ in
            .empty
        }

        viewModel.start()
        await waitUntil {
            viewModel.serverState == .running
            && viewModel.lanReachableAddress == "http://10.0.0.57:12345"
        }
        await waitUntilAsync {
            let counts = await cloudKit.snapshot()
            return counts.startCount == 1
        }

        viewModel.stop()
        await waitUntilAsync {
            let counts = await cloudKit.snapshot()
            return counts.stopCount == 1
        }

        XCTAssertEqual(viewModel.serverState, .stopped)
        XCTAssertNil(viewModel.lanReachableAddress)
        XCTAssertFalse(viewModel.isLANServerStarting)
        XCTAssertNil(viewModel.payload)
    }

    @MainActor
    private func makeViewModel(
        servers: [RelayHTTPServerStub],
        cloudKit: CloudKitTracker = CloudKitTracker(),
        healthCheck: @escaping @Sendable (RelayManagementViewModel, UUID) async throws -> RelayWarmupHealth
    ) -> RelayManagementViewModel {
        let factory = RelayHTTPServerFactory(servers: servers)
        let dependencies = RelayLifecycleDependencies(
            ensureLocalNetworkPermission: {},
            makeHTTPServer: { _, _ in
                factory.make()
            },
            performHealthCheck: healthCheck,
            startCloudKitProcessing: { _ in
                await cloudKit.recordStart()
            },
            stopCloudKitProcessing: {
                Task {
                    await cloudKit.recordStop()
                }
            }
        )
        return RelayManagementViewModel(dependencies: dependencies)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitUntilAsync(
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() >= deadline {
                XCTFail("Timed out waiting for async condition", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class RelayHTTPServerFactory: @unchecked Sendable {
    private let servers: [RelayHTTPServerStub]
    private let lock = NSLock()
    private var nextIndex = 0

    init(servers: [RelayHTTPServerStub]) {
        self.servers = servers
    }

    func make() -> any RelayHTTPServing {
        lock.lock()
        defer { lock.unlock() }
        precondition(nextIndex < servers.count, "No more relay HTTP server stubs configured")
        defer { nextIndex += 1 }
        return servers[nextIndex]
    }
}

private actor RelayHTTPServerStub: RelayHTTPServing {
    private let stateValue: RelayHTTPServer.State
    private let startGate: AsyncGate?
    private var startCallCount = 0
    private var stopCallCount = 0

    init(state: RelayHTTPServer.State, startGate: AsyncGate? = nil) {
        self.stateValue = state
        self.startGate = startGate
    }

    func currentState() -> RelayHTTPServer.State {
        stateValue
    }

    func start() async throws {
        startCallCount += 1
        if let startGate {
            await startGate.wait()
        }
    }

    func stop() async {
        stopCallCount += 1
    }

    func updateConfiguration(_ configuration: RelayServerConfiguration, restart: Bool) async throws {}

    func startCalls() -> Int {
        startCallCount
    }
}

private actor AsyncGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private actor CloudKitTracker {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func recordStart() {
        startCount += 1
    }

    func recordStop() {
        stopCount += 1
    }

    func snapshot() -> (startCount: Int, stopCount: Int) {
        (startCount, stopCount)
    }
}
#endif
