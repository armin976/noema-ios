import XCTest
@testable import NoemaCore

final class PathSafetyTests: XCTestCase {
    func testDatasetPathWithinRootResolves() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("iris.csv")
        try "sepal_length,sepal_width".write(to: file, atomically: true, encoding: .utf8)

        let resolved = try AppDataPathResolver.resolve(path: "iris.csv", allowedRoots: [root], fileManager: fm)
        XCTAssertEqual(resolved.standardizedFileURL, file.standardizedFileURL)
    }

    func testTraversalIsDenied() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        XCTAssertThrowsError(try AppDataPathResolver.resolve(path: "../escape.csv", allowedRoots: [root], fileManager: fm)) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError")
            }
            XCTAssertEqual(appError.code, .pathDenied)
        }
    }
}
