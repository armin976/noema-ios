import XCTest
@testable import Noema

final class BlockMathStyleTests: XCTestCase {
    func testChatStyleUsesLargerFontAndScrollingBehavior() {
        let bodyFontSize = preferredFontSize(.body)
        let style = BlockMathStyle.chat(bodyFontSize: bodyFontSize)

        XCTAssertGreaterThan(style.fontSize, bodyFontSize)
        XCTAssertEqual(style.widthBehavior, .wrapThenScroll)
        XCTAssertFalse(style.useCache)
    }

    func testStandardStyleUsesIntrinsicCachedBehavior() {
        let style = BlockMathStyle.standard(bodyFontSize: preferredFontSize(.body))

        XCTAssertEqual(style.widthBehavior, .intrinsic)
        XCTAssertTrue(style.useCache)
        XCTAssertGreaterThan(style.fontSize, 0)
    }
}

final class ChatMarkdownRenderPlannerTests: XCTestCase {
    func testMacOSPlannerKeepsHeadingSeparateFromBodyText() {
        let entries: [ChatMarkdownPlannerEntry] = [
            .heading(level: 1, content: "Title"),
            .text("Body text")
        ]

        let units = ChatMarkdownRenderPlanner.renderUnits(for: entries, isMacOS: true)

        XCTAssertEqual(units, [
            .entryIndex(0),
            .textMathBlock("Body text")
        ])
    }

    func testMacOSPlannerKeepsMultipleHeadingsAsStandaloneEntries() {
        let entries: [ChatMarkdownPlannerEntry] = [
            .heading(level: 1, content: "H1"),
            .heading(level: 2, content: "H2"),
            .heading(level: 3, content: "H3"),
            .text("Paragraph")
        ]

        let units = ChatMarkdownRenderPlanner.renderUnits(for: entries, isMacOS: true)

        XCTAssertEqual(units, [
            .entryIndex(0),
            .entryIndex(1),
            .entryIndex(2),
            .textMathBlock("Paragraph")
        ])
    }

    func testMacOSPlannerPreservesExistingParagraphAndBulletGrouping() {
        let entries: [ChatMarkdownPlannerEntry] = [
            .text("Intro"),
            .bullet(marker: "•", content: "one"),
            .bullet(marker: "•", content: "two"),
            .text("Outro")
        ]

        let units = ChatMarkdownRenderPlanner.renderUnits(for: entries, isMacOS: true)

        XCTAssertEqual(units, [
            .textMathBlock("Intro\n• one\n• two\nOutro")
        ])
    }

    func testMacOSPlannerKeepsTablesAsSeparateBoundaries() {
        let entries: [ChatMarkdownPlannerEntry] = [
            .heading(level: 2, content: "Section"),
            .text("Intro"),
            .table,
            .text("Outro")
        ]

        let units = ChatMarkdownRenderPlanner.renderUnits(for: entries, isMacOS: true)

        XCTAssertEqual(units, [
            .entryIndex(0),
            .textMathBlock("Intro"),
            .entryIndex(2),
            .textMathBlock("Outro")
        ])
    }
}
