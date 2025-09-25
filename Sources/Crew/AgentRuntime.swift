import Foundation

public struct AgentObservation: Sendable {
    public let content: String
}

public struct AgentResult: Sendable {
    public let messages: [String]
    public let artifacts: [ArtifactRef]
    public let newFacts: [Fact]
    public let toolCalls: Int
    public let tokens: Int
}

public struct AgentContext {
    public let contract: PlanContract
    public let bb: Blackboard

    public init(contract: PlanContract, bb: Blackboard) {
        self.contract = contract
        self.bb = bb
    }
}

public actor AgentRuntime {
    public init() {}

    public func run(task: ProposedTask, context: AgentContext) async throws -> AgentResult {
        var messages: [String] = []
        var artifacts: [ArtifactRef] = []
        var facts: [Fact] = []

        switch task.kind {
        case .plan:
            let planText = "# Plan\n- Understand \(context.contract.goal)\n- Explore datasets\n- Produce report"
            let artifact = ArtifactRef(name: "plan.md", type: .markdown, path: "plan.md", meta: ["owner": task.ownerRole])
            artifacts.append(artifact)
            let fact = Fact(key: "plan", type: .summary, value: Data(planText.utf8))
            facts.append(fact)
            messages.append("Planner drafted plan.md")
        case .schemaInfer:
            let schemaSummary = "Detected schema with inferred numeric + categorical columns"
            let fact = Fact(key: "schema", type: .schema, value: Data(schemaSummary.utf8))
            facts.append(fact)
            messages.append("Analyst inferred schema")
        case .codeGen:
            messages.append("Coder prepared notebook cells")
        case .pythonRun:
            let artifact = ArtifactRef(name: "plot.png", type: .imagePNG, path: "plot.png", meta: ["intent": task.intents.first ?? ""]) 
            artifacts.append(artifact)
            messages.append("Python run produced artifact")
        case .critique:
            let issues = "No blocking issues"
            let fact = Fact(key: "critique", type: .summary, value: Data(issues.utf8))
            facts.append(fact)
            messages.append("Critic reviewed artifacts")
        case .synthesis:
            let report = "## Report\nAll deliverables produced."
            let artifact = ArtifactRef(name: "report.md", type: .markdown, path: "report.md", meta: [:])
            artifacts.append(artifact)
            let doneFact = Fact(key: "done", type: .done, value: Data(report.utf8))
            facts.append(doneFact)
            messages.append("Editor synthesized report")
        }

        return AgentResult(messages: messages, artifacts: artifacts, newFacts: facts, toolCalls: 1, tokens: 256)
    }
}
