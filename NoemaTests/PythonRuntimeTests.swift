import Foundation
import XCTest
@testable import Noema

final class PythonRuntimeTests: XCTestCase {
    func testEmbeddedExecutorReportsUnavailableWhenPathsAreMissing() {
        let executor = EmbeddedPythonExecutor(
            runtimeRootURL: URL(fileURLWithPath: "/tmp/noema-missing-python"),
            stdlibURL: URL(fileURLWithPath: "/tmp/noema-missing-python/lib/python3.14"),
            tempRootURL: FileManager.default.temporaryDirectory.appendingPathComponent("noema-python-tests", isDirectory: true),
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            timeoutClock: Date.init
        )

        XCTAssertFalse(executor.isAvailable)
        XCTAssertNotNil(executor.unavailableReason)
    }

    func testEmbeddedExecutorSmokeTest() async throws {
        let executor = try makeRuntimeExecutor()

        let result = try await executor.execute(code: "print(2 + 2)", timeout: 5)

        XCTAssertEqual(result.stdout, "4\n")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertNil(result.error)
    }

    func testEmbeddedExecutorBlocksNetworkImportsAndExternalReads() async throws {
        let executor = try makeRuntimeExecutor()
        let outsidePath = "/etc/hosts"
        let code = """
        try:
            import socket
        except Exception as exc:
            print(type(exc).__name__)
        try:
            with open("\(outsidePath)", "r", encoding="utf-8") as handle:
                print(handle.read())
        except Exception as exc:
            print(type(exc).__name__)
        """

        let result = try await executor.execute(code: code, timeout: 5)

        XCTAssertTrue(result.stdout.contains("ImportError"))
        XCTAssertTrue(result.stdout.contains("PermissionError"))
    }

    func testEmbeddedExecutorAllowsTempDirectoryFileAccess() async throws {
        let executor = try makeRuntimeExecutor()
        let code = """
        from pathlib import Path
        path = Path("sample.txt")
        path.write_text("ok", encoding="utf-8")
        print(path.read_text(encoding="utf-8"))
        """

        let result = try await executor.execute(code: code, timeout: 5)

        XCTAssertEqual(result.stdout, "ok\n")
        XCTAssertNil(result.error)
    }

    func testEmbeddedExecutorTimesOutBusyLoop() async throws {
        let executor = try makeRuntimeExecutor()
        let result = try await executor.execute(code: "while True:\n    pass", timeout: 1)

        XCTAssertTrue(result.timedOut)
        XCTAssertEqual(result.exitCode, -1)
        XCTAssertNotNil(result.error)
    }

    func testEmbeddedExecutorRecoversAfterFailure() async throws {
        let executor = try makeRuntimeExecutor()
        _ = try await executor.execute(code: "raise ValueError('boom')", timeout: 5)

        let result = try await executor.execute(code: "print('still works')", timeout: 5)

        XCTAssertEqual(result.stdout, "still works\n")
        XCTAssertNil(result.error)
    }

    private func makeRuntimeExecutor(file: StaticString = #filePath) throws -> any PythonExecutor {
#if os(macOS)
        let testsURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let frameworkRoot = projectRoot
            .appendingPathComponent("Frameworks/Python-macOS.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.14", isDirectory: true)
        let stdlibRoot = frameworkRoot.appendingPathComponent("lib/python3.14", isDirectory: true)

        return EmbeddedPythonExecutor(
            runtimeRootURL: frameworkRoot,
            stdlibURL: stdlibRoot,
            tempRootURL: FileManager.default.temporaryDirectory.appendingPathComponent("noema-python-tests", isDirectory: true),
            executableURL: Bundle.main.executableURL,
            timeoutClock: Date.init
        )
#else
        guard let executor = PythonRuntime.makeExecutor() else {
            throw XCTSkip("Embedded Python runtime is not available in the current test host.")
        }
        return executor
#endif
    }
}
