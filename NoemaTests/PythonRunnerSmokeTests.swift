import XCTest
@testable import Noema

@MainActor
final class PythonRunnerSmokeTests: XCTestCase {
    func testPythonExecuteReturnsCachedStdout() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = PythonResultCache(root: root, fileManager: fm)
        defer { try? fm.removeItem(at: root) }

        let code = "print(\"ok\")"
        let key = PyRunKey(code: code, files: [], runnerVersion: PythonExecuteTool.toolVersion)
        let cachedResult = PythonResult(stdout: "ok\n", stderr: "", tables: [], images: [], artifacts: [:])
        try cache.write(key, from: cachedResult)

        let tool = PythonExecuteTool(cache: cache)
        let payload: [String: Any] = [
            "code": code,
            "timeout_ms": 3_000
        ]
        let args = try JSONSerialization.data(withJSONObject: payload)
        let data = try await tool.call(args: args)
        let decoded = try JSONDecoder().decode(PythonExecuteResult.self, from: data)

        XCTAssertFalse(decoded.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
