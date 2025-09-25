import Foundation
import XCTest
@testable import AutoFlow
import NoemaCore

final class AutoFlowTests: XCTestCase {
    func testDatasetMountedTriggersQuickEDAOnce() async throws {
        let bus = AutoFlowEventBus()
        let state = AutoFlowState(profile: .balanced)
        let runner = MockRunner()
        let clock = TestDateProvider()
        let (store, cleanup) = try await makeStore(profile: .balanced)
        defer { cleanup() }
        let engine = AutoFlowEngine(eventBus: bus, state: state, runner: runner, spaceStore: store, dateProvider: { clock.now })
        _ = engine

        try await Task.sleep(nanoseconds: 50_000_000)

        await bus.publish(.datasetMounted(AutoFlowDatasetEvent(url: URL(fileURLWithPath: "/tmp/sample.csv"), sizeMB: 10)))
        try await Task.sleep(nanoseconds: 200_000_000)
        let firstCount = await runner.runCount()
        XCTAssertEqual(firstCount, 1)
        await bus.publish(.datasetMounted(AutoFlowDatasetEvent(url: URL(fileURLWithPath: "/tmp/sample.csv"), sizeMB: 10)))
        try await Task.sleep(nanoseconds: 200_000_000)
        let blockedCount = await runner.runCount()
        XCTAssertEqual(blockedCount, 1, "Rate limit should block second run")

        clock.advance(by: 60)
        await bus.publish(.datasetMounted(AutoFlowDatasetEvent(url: URL(fileURLWithPath: "/tmp/sample.csv"), sizeMB: 10)))
        try await Task.sleep(nanoseconds: 200_000_000)
        let cachedCount = await runner.runCount()
        XCTAssertEqual(cachedCount, 1)
    }

    func testHighNullsTriggersCleanAndCircuitBreaker() async throws {
        let bus = AutoFlowEventBus()
        let state = AutoFlowState(profile: .balanced)
        let runner = MockRunner()
        let clock = TestDateProvider()
        let (store, cleanup) = try await makeStore(profile: .balanced)
        defer { cleanup() }
        let engine = AutoFlowEngine(eventBus: bus, state: state, runner: runner, spaceStore: store, dateProvider: { clock.now })
        _ = engine
        await runner.setErrorMode(.appError)

        try await Task.sleep(nanoseconds: 50_000_000)

        let stats = AutoFlowRunEvent.Stats(dataset: URL(fileURLWithPath: "/tmp/sample.csv"), artifacts: [], nullPercentage: 0.4, madeImages: true)
        await bus.publish(.runFinished(AutoFlowRunEvent(stats: stats)))
        try await Task.sleep(nanoseconds: 200_000_000)
        let firstCleanCount = await runner.runCount()
        XCTAssertEqual(firstCleanCount, 1)

        clock.advance(by: 50)
        await bus.publish(.runFinished(AutoFlowRunEvent(stats: stats)))
        try await Task.sleep(nanoseconds: 200_000_000)
        let secondCleanCount = await runner.runCount()
        XCTAssertEqual(secondCleanCount, 2)

        clock.advance(by: 50)
        await bus.publish(.runFinished(AutoFlowRunEvent(stats: stats)))
        try await Task.sleep(nanoseconds: 200_000_000)
        let circuitCount = await runner.runCount()
        XCTAssertEqual(circuitCount, 2, "Circuit breaker should prevent third run")

        clock.advance(by: 601)
        await runner.setErrorMode(.none)
        await bus.publish(.runFinished(AutoFlowRunEvent(stats: stats)))
        try await Task.sleep(nanoseconds: 200_000_000)
        let recoveredCount = await runner.runCount()
        XCTAssertEqual(recoveredCount, 3)
    }

    func testAggressiveProfileAddsPlots() async throws {
        let bus = AutoFlowEventBus()
        let state = AutoFlowState(profile: .aggressive)
        let runner = MockRunner()
        let clock = TestDateProvider()
        let (store, cleanup) = try await makeStore(profile: .aggressive)
        defer { cleanup() }
        let engine = AutoFlowEngine(eventBus: bus, state: state, runner: runner, spaceStore: store, dateProvider: { clock.now })
        _ = engine

        try await Task.sleep(nanoseconds: 50_000_000)

        let stats = AutoFlowRunEvent.Stats(dataset: URL(fileURLWithPath: "/tmp/sample.csv"), artifacts: [], nullPercentage: 0.1, madeImages: false)
        await bus.publish(.runFinished(AutoFlowRunEvent(stats: stats)))
        try await Task.sleep(nanoseconds: 200_000_000)

        let runs = await runner.recordedRuns()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.identifier, "eda-basic")
        XCTAssertEqual(runs.first?.parameters["mode"], "plots")
    }

    func testCacheSkipPreventsRedundantRuns() async throws {
        let bus = AutoFlowEventBus()
        let state = AutoFlowState(profile: .balanced)
        let runner = MockRunner()
        let clock = TestDateProvider()
        let (store, cleanup) = try await makeStore(profile: .balanced)
        defer { cleanup() }
        let engine = AutoFlowEngine(eventBus: bus, state: state, runner: runner, spaceStore: store, dateProvider: { clock.now })
        _ = engine

        try await Task.sleep(nanoseconds: 50_000_000)

        let datasetEvent = AutoFlowDatasetEvent(url: URL(fileURLWithPath: "/tmp/sample.csv"), sizeMB: 10)
        await bus.publish(.datasetMounted(datasetEvent))
        try await Task.sleep(nanoseconds: 200_000_000)
        let initialCacheCount = await runner.runCount()
        XCTAssertEqual(initialCacheCount, 1)

        clock.advance(by: 60)
        await bus.publish(.datasetMounted(datasetEvent))
        try await Task.sleep(nanoseconds: 200_000_000)
        let cachedCount = await runner.runCount()
        XCTAssertEqual(cachedCount, 1, "Cache should skip duplicate run")
    }
}

private actor MockRunner: AutoFlowPlaybookRunning {
    enum ErrorMode {
        case none
        case appError
    }

    private(set) var runs: [AutoFlowAction.Playbook] = []
    var errorMode: ErrorMode = .none

    func run(_ playbook: AutoFlowAction.Playbook) async throws {
        runs.append(playbook)
        switch errorMode {
        case .none:
            break
        case .appError:
            throw AppError(code: .autoFlow, message: "test")
        }
    }

    func stopCurrentRun() async {}

    func runCount() -> Int {
        runs.count
    }

    func recordedRuns() -> [AutoFlowAction.Playbook] {
        runs
    }

    func setErrorMode(_ mode: ErrorMode) {
        errorMode = mode
    }
}

private func makeStore(profile: SpaceSettings.AutoFlowProfileSetting) async throws -> (SpaceStore, () -> Void) {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    let suite = "spaces-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        throw NSError(domain: "SpaceStore", code: 0, userInfo: nil)
    }
    let store = SpaceStore(fileManager: fm, documentsURL: temp, userDefaults: defaults)
    try await Task.sleep(nanoseconds: 20_000_000)
    let spaces = await store.loadAll()
    if let space = spaces.first {
        try await store.updateSettings(for: space.id, settings: SpaceSettings(autoflowProfile: profile))
        try await store.switchTo(space.id)
    } else {
        let new = try await store.create(name: "Test Space")
        try await store.updateSettings(for: new.id, settings: SpaceSettings(autoflowProfile: profile))
        try await store.switchTo(new.id)
    }
    let cleanup = {
        defaults.removePersistentDomain(forName: suite)
        try? fm.removeItem(at: temp)
    }
    return (store, cleanup)
}

private final class TestDateProvider: @unchecked Sendable {
    private var value: Date
    private let lock = NSLock()

    init(start: Date = Date()) {
        self.value = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}
