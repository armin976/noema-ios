// ModelReadmeLoaderTests.swift
//
//  ModelReadmeLoaderTests.swift
//  Noema
//
//  Created by Armin Stamate on 19/07/2025.
//


import XCTest
@testable import Noema

final class ModelReadmeLoaderTests: XCTestCase {
    func testFirstSentence() {
        let md = "# Title\nThis is first. Second sentence!"
        XCTAssertEqual(ModelReadmeLoader.firstSentence(from: md), "This is first")
    }

    func testPreferredSummaryCard() {
        let res = ModelReadmeLoader.preferredSummary(cardData: "From card", readme: "README sentence")
        XCTAssertEqual(res, "From card")
    }

    func testPreferredSummaryTruncation() {
        let long = String(repeating: "a", count: 200)
        let res = ModelReadmeLoader.preferredSummary(cardData: nil, readme: long)
        XCTAssertEqual(res?.count, 140)
    }
}