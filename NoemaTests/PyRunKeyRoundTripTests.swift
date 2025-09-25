import XCTest
@testable import NoemaCore

final class PyRunKeyRoundTripTests: XCTestCase {
    func testIdentifierRoundTrip() {
        let fileData = Data("sample".utf8)
        let file = PythonMountFile(name: "data.csv", data: fileData, url: URL(fileURLWithPath: "/tmp/data.csv"))
        let key = PyRunKey(code: "print('hello')", files: [file], runnerVersion: "1.0.0")
        let copy = PyRunKey(codeHash: key.codeHash, filesHash: key.filesHash, runnerVersion: key.runnerVersion)
        XCTAssertEqual(copy.identifier, key.identifier)
    }

    func testStableForSameInputs() {
        let files = [PythonMountFile(name: "a.txt", data: Data([1, 2, 3]), url: URL(fileURLWithPath: "/tmp/a.txt"))]
        let keyA = PyRunKey(code: "print('x')", files: files, runnerVersion: "1.0.0")
        let keyB = PyRunKey(code: "print('x')", files: files, runnerVersion: "1.0.0")
        XCTAssertEqual(keyA, keyB)
        XCTAssertEqual(keyA.identifier, keyB.identifier)
    }
}
