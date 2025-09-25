import Foundation

public struct CrewAICompat {
    public struct CrewAIDescription: Codable {
        public var goal: String
        public var roles: [String]
        public var tasks: [String]

        public init(goal: String, roles: [String], tasks: [String]) {
            self.goal = goal
            self.roles = roles
            self.tasks = tasks
        }
    }

    public init() {}

    public func contract(from data: Data) throws -> PlanContract {
        let decoder = JSONDecoder()
        let compat = try decoder.decode(CrewAIDescription.self, from: data)
        let budgets = Budgets(wallClockSec: 300, maxToolCalls: 20, maxTokensTotal: 50_000)
        let deliverables = compat.tasks.enumerated().map { index, task in
            Deliverable(name: "compat_task_\(index)", type: task)
        }
        let gates: [QualityGate] = []
        return PlanContract(goal: compat.goal, allowedTools: ["python.execute", "retriever.search", "notebook.write"], requiredDeliverables: deliverables, budgets: budgets, qualityGates: gates)
    }
}
