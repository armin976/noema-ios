import XCTest
@testable import Crew

final class CrewValidatorTests: XCTestCase {
    func testValidatorFlagsMissingImages() async {
        let bb = Blackboard()
        let gate = QualityGate(name: "images", rule: .minImages(1))
        let failures = await Validator.failures([gate], bb: bb)
        XCTAssertEqual(failures.count, 1)
    }
}
