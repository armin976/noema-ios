import Foundation

public struct PolicyContext {
    public let bb: Blackboard
    public let contract: PlanContract
    public let budgets: Budgets

    public init(bb: Blackboard, contract: PlanContract, budgets: Budgets) {
        self.bb = bb
        self.contract = contract
        self.budgets = budgets
    }
}

public enum TaskKind: String, Codable, Sendable {
    case plan
    case schemaInfer
    case codeGen
    case pythonRun
    case critique
    case synthesis
}

public struct ProposedTask: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var ownerRole: String
    public var kind: TaskKind
    public var inputs: [String]
    public var intents: [String]
    public var priority: Int

    public init(id: UUID = UUID(), ownerRole: String, kind: TaskKind, inputs: [String], intents: [String], priority: Int) {
        self.id = id
        self.ownerRole = ownerRole
        self.kind = kind
        self.inputs = inputs
        self.intents = intents
        self.priority = priority
    }
}

public protocol CrewPolicy {
    var name: String { get }
    func evaluate(event: BlackboardEvent, ctx: PolicyContext) async -> [ProposedTask]
}

// MARK: - Default policies

public struct BootPolicy: CrewPolicy {
    public let name = "BootPolicy"

    public init() {}

    public func evaluate(event: BlackboardEvent, ctx: PolicyContext) async -> [ProposedTask] {
        guard case let .factUpserted(key) = event, key == "goal" else { return [] }
        let existingPlan = await ctx.bb.facts { $0.key == "plan" }
        guard existingPlan.isEmpty else { return [] }
        return [ProposedTask(ownerRole: "Planner", kind: .plan, inputs: [key], intents: ["plan.md"], priority: 100)]
    }
}

public struct EDAPolicy: CrewPolicy {
    public let name = "EDAPolicy"

    public init() {}

    public func evaluate(event: BlackboardEvent, ctx: PolicyContext) async -> [ProposedTask] {
        guard case .factUpserted = event else { return [] }
        let datasets = await ctx.bb.facts { $0.type == .datasetList }
        guard !datasets.isEmpty else { return [] }
        let schemaFacts = await ctx.bb.facts { $0.type == .schema }
        guard schemaFacts.isEmpty else { return [] }
        return [ProposedTask(ownerRole: "Analyst", kind: .schemaInfer, inputs: ["datasetList"], intents: ["schema"], priority: 90)]
    }
}

public struct PlotPolicy: CrewPolicy {
    public let name = "PlotPolicy"

    public init() {}

    public func evaluate(event: BlackboardEvent, ctx: PolicyContext) async -> [ProposedTask] {
        guard case .factUpserted = event else { return [] }
        let schemaFacts = await ctx.bb.facts { $0.type == .schema }
        guard !schemaFacts.isEmpty else { return [] }
        let images = await ctx.bb.artifacts { $0.type == .imagePNG }
        guard images.isEmpty else { return [] }
        return [ProposedTask(ownerRole: "Coder", kind: .pythonRun, inputs: ["schema"], intents: ["plot"], priority: 80)]
    }
}

public struct CritiquePolicy: CrewPolicy {
    public let name = "CritiquePolicy"

    public init() {}

    public func evaluate(event: BlackboardEvent, ctx: PolicyContext) async -> [ProposedTask] {
        switch event {
        case .artifactAdded(let name):
            return [ProposedTask(ownerRole: "Critic", kind: .critique, inputs: [name], intents: ["issues"], priority: 70)]
        case .factUpserted(let key):
            if key == "issue" {
                return [ProposedTask(ownerRole: "Coder", kind: .pythonRun, inputs: [key], intents: ["fix"], priority: 75)]
            }
            return []
        default:
            return []
        }
    }
}

public struct SynthesisPolicy: CrewPolicy {
    public let name = "SynthesisPolicy"

    public init() {}

    public func evaluate(event: BlackboardEvent, ctx: PolicyContext) async -> [ProposedTask] {
        guard case .factUpserted = event else { return [] }
        let failures = await Validator.failures(ctx.contract.qualityGates, bb: ctx.bb)
        guard failures.isEmpty else { return [] }
        let doneFacts = await ctx.bb.facts { $0.type == .done }
        guard doneFacts.isEmpty else { return [] }
        return [ProposedTask(ownerRole: "Editor", kind: .synthesis, inputs: ["plan"], intents: ["report"], priority: 60)]
    }
}
