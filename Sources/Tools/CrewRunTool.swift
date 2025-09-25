import Foundation
import Crew

#if canImport(Noema)
import Noema
#endif

#if !canImport(Noema)
public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var schema: String { get }
    func call(args: Data) async throws -> Data
}
#endif

public struct CrewRunTool: Tool {
    public let name = "crew.run"
    public let description = "Start a local multi-agent run"
    public let schema = """
    {
      "type": "object",
      "properties": {
        "goal": {"type": "string"},
        "dataset_ids": {"type": "array", "items": {"type": "string"}},
        "contract": {"type": "object"}
      },
      "required": ["goal"]
    }
    """

    public init() {}

    struct Input: Codable {
        var goal: String
        var dataset_ids: [String]? 
        var contract: PlanContract?
    }

    struct Output: Codable {
        var run_id: String
        var facts: [String]
        var artifacts: [String]
    }

    public func call(args: Data) async throws -> Data {
        let decoder = JSONDecoder()
        let input = try decoder.decode(Input.self, from: args)
        let contract = input.contract ?? defaultContract(goal: input.goal)
        let bb = Blackboard()
        let store = CrewStore()
        await store.persist(contract: contract)
        let agent = AgentRuntime()
        let taskRuntime = TaskRuntime(agentRuntime: agent, store: store)
        let engine = CrewEngine(bb: bb, policies: defaultPolicies(), taskRuntime: taskRuntime, budgets: contract.budgets)
        let datasetURLs = (input.dataset_ids ?? []).map { URL(fileURLWithPath: $0) }
        _ = try await engine.run(contract: contract, datasetURLs: datasetURLs)

        let facts = await bb.facts { _ in true }
        let artifacts = await bb.artifacts { _ in true }
        let response = Output(run_id: store.runID.uuidString,
                              facts: facts.map { "\($0.key):\(String(data: $0.value, encoding: .utf8) ?? "<binary>")" },
                              artifacts: artifacts.map { $0.name })
        return try JSONEncoder().encode(response)
    }

    private func defaultContract(goal: String) -> PlanContract {
        PlanContract(goal: goal,
                     allowedTools: ["python.execute", "retriever.search", "notebook.write"],
                     requiredDeliverables: [Deliverable(name: "plan.md", type: "markdown"), Deliverable(name: "report.md", type: "markdown")],
                     budgets: Budgets(wallClockSec: 120, maxToolCalls: 12, maxTokensTotal: 20_000),
                     qualityGates: [QualityGate(name: "image", rule: .minImages(1))])
    }

    private func defaultPolicies() -> [CrewPolicy] {
        [BootPolicy(), EDAPolicy(), PlotPolicy(), CritiquePolicy(), SynthesisPolicy()]
    }
}
