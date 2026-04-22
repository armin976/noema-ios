import XCTest
@testable import Noema

final class ManualModelRegistryTests: XCTestCase {
    func testCuratedIncludesBonsai8BAsFeaturedCard() async throws {
        let registry = ManualModelRegistry()
        let curated = try await registry.curated()

        guard let bonsaiIndex = curated.firstIndex(where: { $0.id == "prism-ml/Bonsai-8B-gguf" }) else {
            XCTFail("Bonsai 8b should be included in the curated registry")
            return
        }

        XCTAssertEqual(curated[bonsaiIndex].displayName, "Bonsai 8b")
        XCTAssertLessThan(bonsaiIndex, 6, "Bonsai 8b should stay in the featured card group")
    }
}
