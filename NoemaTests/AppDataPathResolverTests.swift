import XCTest
@testable import NoemaCore

final class AppDataPathResolverTests: XCTestCase {
    func testResolvesFileWithinRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let nested = root.appendingPathComponent("tables", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("result.json")
        try Data("{}".utf8).write(to: file)

        let resolved = try AppDataPathResolver.resolve(path: "/tables/result.json", allowedRoots: [root])
        XCTAssertEqual(resolved.standardizedFileURL, file.standardizedFileURL)
    }

    func testDeniesTraversalOutsideRoot() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        XCTAssertThrowsError(try AppDataPathResolver.resolve(path: "../etc/passwd", allowedRoots: [root])) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError")
            }
            XCTAssertEqual(appError.code, .pathDenied)
        }
    }
}
