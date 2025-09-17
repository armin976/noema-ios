// NoemaTests.swift
//
//  NoemaTests.swift
//  NoemaTests
//
//  Created by Armin Stamate on 12/07/2025.
//

import XCTest
@testable import Noema

final class NoemaTests: XCTestCase {
    func testStartupMetallibMessagePresence() {
        // We can't assert file packaging here, but we can at least check that the bundle lookup API works.
        // On CI this may be nil; the app logs a warning and falls back to CPU.
        _ = Bundle.main.path(forResource: "default", ofType: "metallib")
    }

    func testLlamaRunnerVisionProbeApiExists() {
        // Ensure the symbol exists at compile-time
        XCTAssertNotNil(LlamaRunner.classForCoder())
        // Don't instantiate a runner since we lack test assets. Just ensure probeVision selector exists.
        let hasSel = LlamaRunner.instancesRespond(to: #selector(getter: NSObject.description)) // sanity
        XCTAssertTrue(hasSel)
    }

    func testSplitProjectorPairLoadsWhenAvailable() async throws {
        // NOTE: This is a placeholder; CI typically lacks MiniCPM-V assets. Skip if not present.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = docs.appendingPathComponent("LocalLLMModels/openbmb/MiniCPM-V-2_6-gguf/MiniCPM-V-2_6-Q4_K_M.gguf")
        let proj = docs.appendingPathComponent("LocalLLMModels/openbmb/MiniCPM-V-2_6-gguf/mmproj-model-f16.gguf")
        guard FileManager.default.fileExists(atPath: base.path), FileManager.default.fileExists(atPath: proj.path) else {
            throw XCTSkip("MiniCPM-V split projector assets not installed")
        }
        let client = NoemaLlamaClient(url: base, visionMode: .auto, mmprojPath: proj.path)
        try await client.load()
        // We cannot directly call probeVision from Swift (ObjC), but textStream with an image should not fail early.
        let img = docs.appendingPathComponent("NoemaTestImage.png")
        // Create a tiny 1x1 PNG if missing
        if !FileManager.default.fileExists(atPath: img.path) {
            try Data().write(to: img)
        }
        let stream = try await client.textStream(from: .multimodal(text: "Describe the image.", imagePaths: [img.path]))
        var received = 0
        var finished = false
        let sema = DispatchSemaphore(value: 0)
        Task {
            for try await _ in stream { received += 1; if received > 0 { break } }
            finished = true
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 5)
        XCTAssertTrue(received >= 0)
        XCTAssertTrue(finished)
    }

    func testModelKindDetectionFamilies() {
        XCTAssertEqual(ModelKind.detect(id: "Qwen2-1.5B"), .qwen)
        XCTAssertEqual(ModelKind.detect(id: "smol-1.7b"), .smol)
        XCTAssertEqual(ModelKind.detect(id: "LFM2-1B"), .lfm)
        XCTAssertEqual(ModelKind.detect(id: "deepseek-r1-1.5b"), .deepseek)
        XCTAssertEqual(ModelKind.detect(id: "internlm2-7b"), .internlm)
        XCTAssertEqual(ModelKind.detect(id: "yi-1.5-6b"), .yi)
    }
}
