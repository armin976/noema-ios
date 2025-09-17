// PromptBuilderFamilyTests.swift
import XCTest
@testable import Noema

final class PromptBuilderFamilyTests: XCTestCase {
    private func build(_ family: ModelKind, system: String = "", history: [ChatVM.Msg]) -> String {
        let (p, _, _) = PromptBuilder.build(template: nil, family: family, history: history, system: system)
        return p
    }

    func testSmolInsertsDefaultSystemWhenMissing() {
        let prompt = build(.smol, history: [ChatVM.Msg(role: "user", text: "Hi")])
        XCTAssertTrue(prompt.contains("<|im_start|>system"))
        XCTAssertTrue(prompt.contains("SmolLM"))
        XCTAssertTrue(prompt.hasPrefix("<|im_start|>"))
    }

    func testInternLMUsesChatMLAndSystemDefault() {
        let prompt = build(.internlm, history: [ChatVM.Msg(role: "user", text: "Hi")])
        XCTAssertTrue(prompt.contains("<|im_start|>system"))
        XCTAssertTrue(prompt.contains("InternLM"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant"))
    }

    func testDeepSeekBosAndRoleTags() {
        let prompt = build(.deepseek, history: [ChatVM.Msg(role: "user", text: "你好")])
        XCTAssertTrue(prompt.contains("<攼 begin▁of▁sentence放>"))
        XCTAssertTrue(prompt.contains("<|User|>"))
        XCTAssertTrue(prompt.contains("<|Assistant|>"))
    }

    func testYiAddsStartOfTextAndDefaultSystemWhenMissing() {
        let prompt = build(.yi, history: [ChatVM.Msg(role: "user", text: "Hi")])
        XCTAssertTrue(prompt.hasPrefix("<|startoftext|>"))
        XCTAssertTrue(prompt.contains("<|im_start|>system"))
    }
}
