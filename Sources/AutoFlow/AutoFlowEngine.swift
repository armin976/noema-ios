import Foundation
import NoemaCore

public protocol AutoFlowPlaybookRunning: Sendable {
    func run(_ playbook: AutoFlowAction.Playbook) async throws
    func stopCurrentRun() async
}

public struct AutoFlowRunLog: Sendable, Equatable {
    public let action: AutoFlowAction
    public let startedAt: Date
    public let finishedAt: Date?
    public let outcome: Outcome

    public enum Outcome: Sendable, Equatable {
        case success
        case skipped(reason: String)
        case failure(message: String)
    }
}

public enum AutoFlowEngineError: Error, Sendable {
    case timeout
}

public actor AutoFlowEngine {
    private enum Constants {
        static let runnerTimeout: TimeInterval = 120
    }

    public static let shared = AutoFlowEngine()

    private let eventBus: AutoFlowEventBus
    private let state: AutoFlowState
    private let runner: AutoFlowPlaybookRunning
    private var status: AutoFlowStatus = AutoFlowStatus()
    private var statusContinuations: [UUID: AsyncStream<AutoFlowStatus>.Continuation] = [:]
    private var subscriptionTask: Task<Void, Never>?
    private let dateProvider: () -> Date
    private let isoFormatter: ISO8601DateFormatter = ISO8601DateFormatter()

    public init(eventBus: AutoFlowEventBus = .shared,
                state: AutoFlowState = AutoFlowState(),
                runner: AutoFlowPlaybookRunning = AutoFlowNoopRunner(),
                dateProvider: @escaping () -> Date = Date.init) {
        self.eventBus = eventBus
        self.state = state
        self.runner = runner
        self.dateProvider = dateProvider
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        Task { await bootstrap() }
    }

    deinit {
        subscriptionTask?.cancel()
    }

    public func subscribeStatus() -> AsyncStream<AutoFlowStatus> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { [id] _ in
                Task { await self.removeStatusContinuation(id) }
            }
            Task { await self.storeStatusContinuation(continuation, id: id) }
            continuation.yield(status)
        }
    }

    public func updateProfile(_ profile: AutoFlowProfile) async {
        await state.updateProfile(profile)
        await broadcastStatus()
    }

    public func updateToggles(_ toggles: AutoFlowToggles) async {
        await state.updateToggles(toggles)
        await broadcastStatus()
    }

    public func setKillSwitch(enabled: Bool) async {
        await state.setKillSwitch(enabled)
        await broadcastStatus()
    }

    public func pauseForTenMinutes() async {
        let until = dateProvider().addingTimeInterval(600)
        await state.pause(until: until)
        await broadcastStatus()
    }

    public func resume() async {
        await state.clearPause()
        await broadcastStatus()
    }

    public func stop() async {
        await runner.stopCurrentRun()
        await pauseForTenMinutes()
    }

    private func listenForEvents() async {
        let stream = await eventBus.subscribe()
        for await event in stream {
            await handle(event)
        }
    }

    private func bootstrap() async {
        subscriptionTask = Task { await listenForEvents() }
    }

    private func handle(_ event: AutoFlowEvent) async {
        let now = dateProvider()
        await log(event: "event", payload: ["type": String(describing: event), "timestamp": isoFormatter.string(from: now)])

        if case let .errorOccurred(appError) = event {
            await state.registerActionFailure(at: now)
            await broadcastStatus(with: .paused(reason: ErrorPresenter.present(appError)))
            return
        }

        let guardrail = await state.guardrailState(now: now)
        switch guardrail {
        case .disabled:
            await broadcastStatus(with: .paused(reason: "AutoFlow disabled"))
            return
        case let .manuallyPaused(until):
            let reason = "Paused until \(isoFormatter.string(from: until))"
            await broadcastStatus(with: .paused(reason: reason))
            return
        case let .circuitOpen(until):
            let reason = "Circuit open until \(isoFormatter.string(from: until))"
            await broadcastStatus(with: .paused(reason: reason))
            return
        case let .rateLimited(until):
            let reason = "Rate limited until \(isoFormatter.string(from: until))"
            await broadcastStatus(with: .paused(reason: reason))
            return
        case .ready:
            break
        }

        let preferences = await state.preferences(now: now)
        let context = AutoFlowRuleContext(preferences: preferences, now: now)
        guard let action = AutoFlowRuleEngine.action(for: event, context: context) else {
            await broadcastStatus(with: .idle)
            return
        }

        if await state.shouldSkipDueToCache(action, now: now) {
            await log(event: "skip", payload: ["reason": "cache", "action": action.playbook.identifier])
            await broadcastStatus(with: .paused(reason: "Cached within 24h"))
            return
        }

        await broadcastStatus(with: .running(description: action.playbook.description))
        do {
            try await execute(action, now: now)
            await state.registerActionSuccess(action, at: now)
            await broadcastStatus(with: .idle)
        } catch let error as AutoFlowEngineError {
            await handleFailure(action: action, error: error, now: now)
        } catch let error as AppError {
            await handleFailure(action: action, error: error, now: now)
        } catch {
            let wrapped = AppError(code: .unknown, message: error.localizedDescription)
            await handleFailure(action: action, error: wrapped, now: now)
        }
    }

    private func execute(_ action: AutoFlowAction, now: Date) async throws {
        await log(event: "start", payload: [
            "action": action.playbook.identifier,
            "dataset": action.playbook.dataset?.absoluteString ?? "",
            "parameters": action.playbook.parameters,
        ])

        do {
            try await withTimeout(seconds: Constants.runnerTimeout) { [self] in
                try await self.runner.run(action.playbook)
            }
        } catch {
            await log(event: "failure", payload: ["message": error.localizedDescription])
            throw error
        }

        await log(event: "success", payload: ["action": action.playbook.identifier])
    }

    private func handleFailure(action: AutoFlowAction, error: Error, now: Date) async {
        if let error = error as? AutoFlowEngineError, case .timeout = error {
            await state.registerActionFailure(at: now)
            let appError = AppError(code: .autoFlow, message: "AutoFlow timed out")
            await broadcastStatus(with: .paused(reason: ErrorPresenter.present(appError)))
            await log(event: "failure", payload: ["message": "timeout", "action": action.playbook.identifier])
            return
        }

        let appError: AppError
        if let error = error as? AppError {
            appError = error
        } else {
            appError = AppError(code: .autoFlow, message: error.localizedDescription)
        }
        await state.registerActionFailure(at: now)
        await log(event: "failure", payload: ["message": appError.message, "code": appError.code.rawValue])
        await broadcastStatus(with: .paused(reason: ErrorPresenter.present(appError)))
    }

    private func log(event: String, payload: [String: Any]) async {
        var enriched = payload
        enriched["event"] = event
        enriched["timestamp"] = isoFormatter.string(from: dateProvider())
        guard let data = try? JSONSerialization.data(withJSONObject: enriched, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        let logURL = logFileURL()
        ensureLogDirectoryExists(url: logURL)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            if let data = string.appending("\n").data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
            try? handle.close()
        } else {
            try? string.appending("\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private func ensureLogDirectoryExists(url: URL) {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func logFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("AutoFlow", isDirectory: true).appendingPathComponent("elog.jsonl")
    }

    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                let ns = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw AutoFlowEngineError.timeout
            }
            guard let result = try await group.next() else {
                throw AutoFlowEngineError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private func broadcastStatus() async {
        let status = await state.status(now: dateProvider())
        await broadcastStatus(with: status.phase)
    }

    private func broadcastStatus(with phase: AutoFlowStatus.Phase) async {
        let info = await state.status(now: dateProvider())
        status = AutoFlowStatus(phase: phase, lastActionAt: info.lastActionAt)
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
    }

    private func storeStatusContinuation(_ continuation: AsyncStream<AutoFlowStatus>.Continuation, id: UUID) {
        statusContinuations[id] = continuation
    }

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations[id] = nil
    }
}

public struct AutoFlowNoopRunner: AutoFlowPlaybookRunning {
    public init() {}

    public func run(_ playbook: AutoFlowAction.Playbook) async throws {}

    public func stopCurrentRun() async {}
}
