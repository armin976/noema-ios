import Foundation
import XCTest
import NoemaPackages
@testable import Noema

final class Gemma4LoopbackTests: XCTestCase {
    func testGemma4DetectionEnablesTemplateDrivenMessages() {
        XCTAssertTrue(TemplateDrivenModelSupport.isGemma4(modelID: "google/gemma-4-31B-it"))
        XCTAssertTrue(TemplateDrivenModelSupport.usesTemplateDrivenMessages(modelID: "google/gemma-4-31B-it"))
        XCTAssertFalse(TemplateDrivenModelSupport.isQwen35(modelID: "google/gemma-4-31B-it"))
    }

    func testGemma4TemplateResolvesToBundledInterleavedTemplate() throws {
        let path = try XCTUnwrap(
            TemplateDrivenModelSupport.resolveChatTemplateFile(modelID: "google/gemma-4-31B-it")
        )
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(contents.contains("<|turn>system"))
        XCTAssertTrue(contents.contains("<|turn>model"))
        XCTAssertTrue(contents.contains("add_generation_prompt"))
    }

    func testGemma4LoopbackConfigurationUsesBundledTemplateAndDefaults() throws {
        let config = TemplateDrivenModelSupport.loopbackStartConfiguration(
            modelID: "google/gemma-4-31B-it",
            ggufPath: "/tmp/google-gemma-4-31B-it.gguf",
            mmprojPath: nil
        )

        XCTAssertEqual(config.chatTemplateFile, TemplateDrivenModelSupport.resolveChatTemplateFile(modelID: "google/gemma-4-31B-it"))
        XCTAssertTrue(config.useJinja)
        XCTAssertEqual(config.cacheRamMiB, 2048)
        XCTAssertEqual(config.ctxCheckpoints, 2)
        XCTAssertNil(config.reasoningBudget)
    }

    func testGemma4AliasDetectionUsesMetadataTemplate() throws {
        let root = try makeTemporaryDirectory()
        let weight = root.appendingPathComponent("custom-interleaved.gguf")
        let template = root.appendingPathComponent("chat_template.jinja")
        FileManager.default.createFile(atPath: weight.path, contents: Data("GGUF".utf8))
        FileManager.default.createFile(
            atPath: template.path,
            contents: Data(
                """
                <|turn>system
                hello
                <|turn>model
                {% if add_generation_prompt %}go{% endif %}
                """.utf8
            )
        )

        XCTAssertTrue(TemplateDrivenModelSupport.isGemma4(modelURL: weight))
        XCTAssertTrue(TemplateDrivenModelSupport.usesTemplateDrivenMessages(modelURL: weight))
        XCTAssertEqual(TemplateDrivenModelSupport.templateLabel(modelURL: weight), "gemma4-interleaved")
        let config = TemplateDrivenModelSupport.loopbackStartConfiguration(
            modelURL: weight,
            ggufPath: weight.path,
            mmprojPath: nil
        )
        XCTAssertTrue(config.useJinja)
        XCTAssertEqual(config.cacheRamMiB, 2048)
        XCTAssertEqual(config.ctxCheckpoints, 2)
    }

    func testGemma4LoopbackRequestPlanUsesStructuredChatCompletion() throws {
        let client = NoemaLlamaClient(url: URL(fileURLWithPath: "/tmp/google-gemma-4-31B-it.gguf"))
        let input = LLMInput(.messages([ChatMessage(role: "user", content: "Hello Gemma 4")]))

        let plan = client.buildLoopbackRequestPlan(for: input, forceNonStreaming: false)

        XCTAssertEqual(plan.endpoint, "/v1/chat/completions")
        XCTAssertEqual(plan.requestMode, "chat_completions")
        XCTAssertEqual(plan.body["add_generation_prompt"] as? Bool, true)
        XCTAssertNil(plan.body["reasoning_format"])
        let messages = try XCTUnwrap(plan.body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "Hello Gemma 4")
    }

    @MainActor
    func testGemma4StructuredLoopbackInputIsSelectedForLoadedGGUF() {
        let vm = ChatVM()
        vm.setLoadedStateForTesting(
            modelLoaded: true,
            loadedURL: URL(fileURLWithPath: "/tmp/google-gemma-4-31B-it.gguf"),
            loadedFormat: .gguf
        )

        let history: [ChatVM.Msg] = [
            .init(role: "🧑‍💻", text: "Summarize the report", timestamp: Date())
        ]

        let input = vm.structuredLoopbackInput(for: history)

        guard case .messages(let messages)? = input?.content else {
            return XCTFail("Expected structured loopback input for Gemma 4")
        }

        XCTAssertEqual(messages.first?.role, "user")
        XCTAssertEqual(messages.first?.content, "Summarize the report")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}
