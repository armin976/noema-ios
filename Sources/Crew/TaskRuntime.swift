import Foundation

public struct TaskRuntime {
    public struct Outcome: Sendable, Codable {
        public let toolCalls: Int
        public let tokens: Int
    }

    private let agentRuntime: AgentRuntime
    private let validator: Validator
    private let store: CrewStore?

    public init(agentRuntime: AgentRuntime, validator: Validator = Validator(), store: CrewStore? = nil) {
        self.agentRuntime = agentRuntime
        self.validator = validator
        self.store = store
    }

    public func execute(task: ProposedTask, contract: PlanContract, bb: Blackboard) async throws -> Outcome {
        let context = AgentContext(contract: contract, bb: bb)
        let result = try await agentRuntime.run(task: task, context: context)

        for fact in result.newFacts {
            try await bb.upsertFact(fact)
        }
        for artifact in result.artifacts {
            await bb.addArtifact(artifact)
        }

        let outcome = Outcome(toolCalls: result.toolCalls, tokens: result.tokens)
        if let store {
            await store.append(event: CrewRunEvent(task: task, messages: result.messages, outcome: outcome))
        }
        _ = validator // reserved for future hook
        return outcome
    }
}
