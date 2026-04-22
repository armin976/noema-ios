import XCTest
@testable import Noema

final class ChatSendBehaviorTests: XCTestCase {
    func testFromReturnsDefaultForUnknownRawValue() {
        XCTAssertEqual(ChatSendBehavior.from("unknown"), .defaultValue)
    }

    func testFromReturnsStoredValueWhenRecognized() {
        XCTAssertEqual(ChatSendBehavior.from(ChatSendBehavior.returnKeySends.rawValue), .returnKeySends)
    }
}
