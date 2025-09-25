import Foundation

public struct Counters: Sendable {
    public var toolCalls: Int = 0
    public var tokens: Int = 0
    public var started: Date = Date()

    public init() {}

    public mutating func register(toolCalls: Int, tokens: Int) {
        self.toolCalls += toolCalls
        self.tokens += tokens
    }

    public func within(_ budgets: Budgets) -> Bool {
        return Date().timeIntervalSince(started) < Double(budgets.wallClockSec)
        && toolCalls <= budgets.maxToolCalls
        && tokens <= budgets.maxTokensTotal
    }
}

public actor CrewEngine {
    public let bb: Blackboard
    private let policies: [CrewPolicy]
    private let taskRuntime: TaskRuntime
    private let budgets: Budgets
    private var counters = Counters()

    public init(bb: Blackboard, policies: [CrewPolicy], taskRuntime: TaskRuntime, budgets: Budgets) {
        self.bb = bb
        self.policies = policies
        self.taskRuntime = taskRuntime
        self.budgets = budgets
    }

    public struct RunHandle: Sendable { public let id: UUID }

    @discardableResult
    public func run(contract: PlanContract, datasetURLs: [URL]) async throws -> RunHandle {
        let stream = await bb.events()
        try await bb.upsertFact(Fact(key: "goal", type: .goal, value: try JSONEncoder().encode(contract.goal)))
        try await bb.upsertFact(Fact(key: "datasetList", type: .datasetList, value: try JSONEncoder().encode(datasetURLs.map(\.lastPathComponent))))
        for await event in stream {
            let ctx = PolicyContext(bb: bb, contract: contract, budgets: budgets)
            let proposals = await withTaskGroup(of: [ProposedTask].self) { group -> [ProposedTask] in
                for policy in policies {
                    group.addTask { await policy.evaluate(event: event, ctx: ctx) }
                }
                return await group.reduce(into: []) { $0.append(contentsOf: $1) }
            }
            let sorted = proposals.sorted { $0.priority > $1.priority }
            for task in sorted {
                guard counters.within(budgets) else {
                    await bb.emitWarning("Budget exceeded before scheduling task \(task.id)")
                    break
                }
                let outcome = try await taskRuntime.execute(task: task, contract: contract, bb: bb)
                counters.register(toolCalls: outcome.toolCalls, tokens: outcome.tokens)
            }
            let doneFacts = await bb.facts { $0.type == .done }
            if !doneFacts.isEmpty { break }
        }
        return RunHandle(id: UUID())
    }
}
