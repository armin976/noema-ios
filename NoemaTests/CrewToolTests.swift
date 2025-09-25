import XCTest
@testable import CrewTools

final class CrewToolTests: XCTestCase {
    func testCrewRunToolProducesArtifacts() async throws {
        let tool = CrewRunTool()
        let request = try JSONEncoder().encode(["goal": "Test goal"])
        let data = try await tool.call(args: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        XCTAssertFalse(response.run_id.isEmpty)
        XCTAssertFalse(response.facts.isEmpty)
    }

    private struct Response: Decodable {
        let run_id: String
        let facts: [String]
        let artifacts: [String]
    }
}
