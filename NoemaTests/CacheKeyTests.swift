import XCTest
@testable import NoemaCore

final class CacheKeyTests: XCTestCase {
    func testIdenticalInputsProduceSameKey() {
        let fileURL = URL(fileURLWithPath: "/tmp/sample.csv")
        let file = PythonMountFile(url: fileURL, data: Data("alpha".utf8))
        let first = PyRunKey(code: "print('ok')", files: [file], runnerVersion: "1.0.0")
        let second = PyRunKey(code: "print('ok')", files: [file], runnerVersion: "1.0.0")

        XCTAssertEqual(first.identifier, second.identifier)
    }

    func testDifferentInputsChangeKey() {
        let url = URL(fileURLWithPath: "/tmp/sample.csv")
        let fileA = PythonMountFile(url: url, data: Data([0x01, 0x02, 0x03]))
        let fileB = PythonMountFile(url: url, data: Data([0x01, 0x02, 0x04]))

        let first = PyRunKey(code: "print('ok')", files: [fileA], runnerVersion: "1.0.0")
        let second = PyRunKey(code: "print('ok')", files: [fileB], runnerVersion: "1.0.0")

        XCTAssertNotEqual(first.identifier, second.identifier)
    }
}
