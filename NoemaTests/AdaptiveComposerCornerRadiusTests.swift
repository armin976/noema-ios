import XCTest
@testable import Noema

@MainActor
final class AdaptiveComposerCornerRadiusTests: XCTestCase {
    func testReturnsCollapsedHalfHeightRadiusAtCollapsedHeight() {
        let radius = UIConstants.adaptiveComposerCornerRadius(
            currentHeight: 48,
            collapsedHeight: 48,
            expandedHeight: 96,
            expandedRadius: 15
        )

        XCTAssertEqual(radius, 24, accuracy: 0.001)
    }

    func testInterpolatesTowardExpandedRadiusBetweenBounds() {
        let radius = UIConstants.adaptiveComposerCornerRadius(
            currentHeight: 72,
            collapsedHeight: 48,
            expandedHeight: 96,
            expandedRadius: 12
        )

        XCTAssertEqual(radius, 18, accuracy: 0.001)
    }

    func testClampsToExpandedRadiusPastExpandedHeight() {
        let radius = UIConstants.adaptiveComposerCornerRadius(
            currentHeight: 140,
            collapsedHeight: 52,
            expandedHeight: 132,
            expandedRadius: 20
        )

        XCTAssertEqual(radius, 20, accuracy: 0.001)
    }

    func testHandlesEqualCollapsedAndExpandedHeights() {
        let radius = UIConstants.adaptiveComposerCornerRadius(
            currentHeight: 52,
            collapsedHeight: 52,
            expandedHeight: 52,
            expandedRadius: 20
        )

        XCTAssertEqual(radius, 26, accuracy: 0.001)
    }
}
