import XCTest
@testable import Noema

final class StreamChunkMergerTests: XCTestCase {
    func testDeltaModePreservesRepeatedDigits() {
        var merger = StreamChunkMerger(mode: .delta)
        var text = ""

        merger.append("1", to: &text)
        merger.append("1", to: &text)

        XCTAssertEqual(text, "11")
    }

    func testDeltaModePreservesRepeatedDigitsInsideThinkBlock() {
        var merger = StreamChunkMerger(mode: .delta)
        var text = ""

        merger.append("<think>", to: &text)
        merger.append("1", to: &text)
        merger.append("1", to: &text)
        merger.append("</think>", to: &text)

        XCTAssertEqual(text, "<think>11</think>")
    }

    func testDeltaModePreservesRepeatedDigitsAfterToolAnchor() {
        var merger = StreamChunkMerger(mode: .delta)
        var text = noemaToolAnchorToken

        merger.append("1", to: &text)
        merger.append("1", to: &text)

        XCTAssertEqual(text, noemaToolAnchorToken + "11")
    }

    func testUnknownModeDetectsCumulativeChunksWithoutDuplication() {
        var merger = StreamChunkMerger()
        var text = ""

        merger.append("1", to: &text)
        merger.append("11", to: &text)
        merger.append("111", to: &text)

        XCTAssertEqual(text, "111")
        XCTAssertEqual(merger.mode, .cumulative)
    }

    func testUnknownModePreservesOverlappingChunks() {
        var merger = StreamChunkMerger()
        var text = ""

        merger.append("Hello", to: &text)
        merger.append("lo world", to: &text)

        XCTAssertEqual(text, "Hello world")
    }
}
