import Foundation
import XCTest
import NoemaPackages
@testable import Noema

final class LoopbackStartupPlannerTests: XCTestCase {
    func testConservativeSettingsClampAndDisableAggressiveFlags() {
        var requested = ModelSettings.default(for: .gguf)
        requested.contextLength = 65_536
        requested.gpuLayers = -1
        requested.kvCacheOffload = true
        requested.flashAttention = true
        requested.disableWarmup = false
        requested.useMmap = false
        requested.cpuThreads = 0

        let recovered = LoopbackStartupPlanner.conservativeSettings(
            modelURL: URL(fileURLWithPath: "/tmp/Qwen3.5-4B-Q4_K_M.gguf"),
            requestedSettings: requested
        )

        XCTAssertLessThanOrEqual(Int(recovered.contextLength), 4096)
        XCTAssertEqual(recovered.gpuLayers, 0)
        XCTAssertFalse(recovered.kvCacheOffload)
        XCTAssertFalse(recovered.flashAttention)
        XCTAssertTrue(recovered.disableWarmup)
        XCTAssertTrue(recovered.useMmap)
        XCTAssertGreaterThanOrEqual(recovered.cpuThreads, 1)
    }

    func testTemplateDiagnosticsChooseTemplateFreeRetry() {
        let diagnostics = LlamaServerBridge.StartDiagnostics(
            code: "model_load_failed",
            message: "Chat template initialization failed: jinja parse error",
            lastHTTPStatus: 503,
            elapsedMs: 1200,
            progress: 0.2,
            httpReady: false
        )
        let requested = ModelSettings.default(for: .gguf)

        let retryPlan = LoopbackStartupPlanner.makeRetryPlan(
            modelURL: URL(fileURLWithPath: "/tmp/Qwen3.5-4B-Q4_K_M.gguf"),
            requestedSettings: requested,
            mmprojPath: "/tmp/model.mmproj",
            diagnostics: diagnostics
        )

        XCTAssertTrue(retryPlan.droppedTemplateOverride)
        XCTAssertNil(retryPlan.configuration.chatTemplateFile)
        XCTAssertFalse(retryPlan.configuration.useJinja)
        XCTAssertNil(retryPlan.configuration.reasoningBudget)
        XCTAssertEqual(retryPlan.configuration.mmprojPath, "/tmp/model.mmproj")
    }

    func testFailureMessageIncludesReasonAndRetryStatus() {
        let diagnostics = LlamaServerBridge.StartDiagnostics(
            code: "ready_timeout",
            message: "Loopback server never became ready.",
            lastHTTPStatus: 503,
            elapsedMs: 3400,
            progress: 0.87,
            httpReady: false
        )

        let message = LoopbackStartupPlanner.formatFailureMessage(diagnostics, retryAttempted: true)

        XCTAssertTrue(message.contains("Failed to start local GGUF runtime."))
        XCTAssertTrue(message.contains("Reason: Loopback server never became ready."))
        XCTAssertTrue(message.contains("Status: 503, progress: 87%, retry: attempted"))
    }

    func testConservativeSettingsUsesResolvedKVCacheQuantization() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let ggufURL = root.appendingPathComponent("model.gguf")
        try writeMinimalGGUF(to: ggufURL, contextLength: 131_072)
        try expandSparseFile(at: ggufURL, toSize: gib(1))

        var requestedF16 = ModelSettings.default(for: .gguf)
        requestedF16.contextLength = 65_536
        requestedF16.kCacheQuant = .f16
        requestedF16.vCacheQuant = .f16
        requestedF16.flashAttention = false

        var requestedQ4 = requestedF16
        requestedQ4.kCacheQuant = .q4_1

        let budget = gib(2) + mib(512)

        let recoveredF16 = LoopbackStartupPlanner.conservativeSettings(
            modelURL: ggufURL,
            requestedSettings: requestedF16,
            budgetBytesOverride: budget
        )
        let recoveredQ4 = LoopbackStartupPlanner.conservativeSettings(
            modelURL: ggufURL,
            requestedSettings: requestedQ4,
            budgetBytesOverride: budget
        )

        XCTAssertGreaterThan(Int(recoveredQ4.contextLength), Int(recoveredF16.contextLength))
    }
}

private extension LoopbackStartupPlannerTests {
    func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func writeMinimalGGUF(to url: URL, contextLength: UInt32) throws {
        var data = Data()
        data.append(Data("GGUF".utf8))
        append(UInt32(3), to: &data)
        append(UInt64(0), to: &data)
        append(UInt64(1), to: &data)

        let key = Data("llama.n_ctx_train".utf8)
        append(UInt64(key.count), to: &data)
        data.append(key)
        append(UInt32(4), to: &data)
        append(contextLength, to: &data)

        try data.write(to: url)
    }

    func expandSparseFile(at url: URL, toSize size: Int64) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }

    func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { rawBuffer in
            data.append(contentsOf: rawBuffer)
        }
    }

    func gib(_ value: Int64) -> Int64 {
        value * 1_073_741_824
    }

    func mib(_ value: Int64) -> Int64 {
        value * 1_048_576
    }
}
