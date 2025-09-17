// FormatDetectionTests.swift
import XCTest
@testable import Noema

final class FormatDetectionTests: XCTestCase {
    func testDetectGGUF() {
        let url = URL(fileURLWithPath: "/tmp/model.gguf")
        XCTAssertEqual(ModelFormat.detect(from: url), .gguf)
    }

    func testDetectGGMLBin() {
        let url = URL(fileURLWithPath: "/tmp/model.bin")
        XCTAssertEqual(ModelFormat.detect(from: url), .gguf)
    }

    func testDetectMLX() {
        let url = URL(fileURLWithPath: "/tmp/model.mlx")
        XCTAssertEqual(ModelFormat.detect(from: url), .mlx)
    }

    func testPromptTemplateSelectionPrefersGGUF() {
        // Ensure that when a chat_template is present in GGUF, it is applied via ModelSettings
        // This is a smoke test: we cannot create a real GGUF here, but we can ensure the pipeline prefers template strings when provided.
        var settings = ModelSettings.default(for: .gguf)
        settings.promptTemplate = "<|im_start|>system\nHello\n<|im_end|>\n<|im_start|>assistant\n"
        // Serialize a trivial two-message conversation
        let history = [ChatVM.Msg(role: "user", text: "Hi"), ChatVM.Msg(role: "assistant", text: "Hello")]
        let (rendered, _, _) = PromptBuilder.build(template: settings.promptTemplate, family: .qwen, history: history, system: "")
        XCTAssertTrue(rendered.contains("<|im_start|>assistant"))
    }
}
