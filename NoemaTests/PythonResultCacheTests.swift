import XCTest
@testable import Noema

final class PythonResultCacheTests: XCTestCase {
    func testCacheKeyDeterministic() {
        let file = PythonMountFile(url: URL(fileURLWithPath: "/tmp/sample.txt"), data: Data("sample".utf8))
        let keyA = PyRunKey(code: "print('hello')", files: [file], runnerVersion: "1")
        let keyB = PyRunKey(code: "print('hello')", files: [file], runnerVersion: "1")
        let keyC = PyRunKey(code: "print('goodbye')", files: [file], runnerVersion: "1")

        XCTAssertEqual(keyA, keyB)
        XCTAssertEqual(keyA.hashValue, keyB.hashValue)
        XCTAssertNotEqual(keyA, keyC)
    }

    func testCacheRoundTrip() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = PythonResultCache(root: temporaryRoot)
        let key = PyRunKey(code: "print('round trip')", files: [], runnerVersion: "1")
        let result = PythonResult(
            stdout: "output",
            stderr: "errors",
            tables: [Data("table".utf8)],
            images: [Data([0x01, 0x02, 0x03])],
            artifacts: ["foo": Data("bar".utf8)]
        )

        try cache.write(key, from: result)
        guard let entry = cache.lookup(key) else {
            return XCTFail("Expected cache entry")
        }

        let recovered = try entry.loadResult()
        XCTAssertEqual(recovered.stdout, result.stdout)
        XCTAssertEqual(recovered.stderr, result.stderr)
        XCTAssertEqual(recovered.tables, result.tables)
        XCTAssertEqual(recovered.images, result.images)
        XCTAssertEqual(recovered.artifacts["foo"], result.artifacts["foo"])

        let metaData = try Data(contentsOf: entry.metaURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meta = try decoder.decode(PyRunCacheMeta.self, from: metaData)
        XCTAssertTrue(meta.imageFiles.contains(where: { $0.hasSuffix(".png") }))
        XCTAssertEqual(meta.artifacts.keys.sorted(), ["foo"])
    }
}
