import XCTest
@testable import Crew

final class CrewEngineTests: XCTestCase {
    func testCrewRunProducesDoneFact() async throws {
        let bb = Blackboard()
        let agent = AgentRuntime()
        let store = CrewStore()
        let runtime = TaskRuntime(agentRuntime: agent, store: store)
        let contract = PlanContract(goal: "Explore sample.csv",
                                    allowedTools: ["python.execute"],
                                    requiredDeliverables: [],
                                    budgets: Budgets(wallClockSec: 5, maxToolCalls: 10, maxTokensTotal: 1000),
                                    qualityGates: [])
        let engine = CrewEngine(bb: bb,
                                policies: [BootPolicy(), EDAPolicy(), PlotPolicy(), CritiquePolicy(), SynthesisPolicy()],
                                taskRuntime: runtime,
                                budgets: contract.budgets)
        _ = try await engine.run(contract: contract, datasetURLs: [])
        let doneFacts = await bb.facts { $0.type == .done }
        XCTAssertFalse(doneFacts.isEmpty)
    }
}
