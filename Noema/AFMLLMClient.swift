import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AFMLLMClientError: LocalizedError {
    case unsupportedDevice
    case unavailable(AppleFoundationModelUnavailableReason)
    case frameworkUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return String(localized: "Apple Foundation Models are not supported on this device.")
        case .unavailable(let reason):
            return reason.message
        case .frameworkUnavailable:
            return String(localized: "Foundation Models framework is unavailable in this build.")
        }
    }
}

final class AFMLLMClient: @unchecked Sendable {
    #if canImport(FoundationModels)
    private var sessionStorage: AnyObject?
    #endif

    private let guardrailsMode: AFMGuardrailsMode
    private let onToolSummary: (@Sendable (AFMToolExecutionSummary) async -> Void)?
    private var systemPrompt: String?

    init(
        guardrailsMode: AFMGuardrailsMode = .default,
        onToolSummary: (@Sendable (AFMToolExecutionSummary) async -> Void)? = nil
    ) {
        self.guardrailsMode = guardrailsMode
        self.onToolSummary = onToolSummary
    }

    func load() async throws {
        let availability = AppleFoundationModelAvailability.current
        guard availability.isSupportedDevice else {
            throw AFMLLMClientError.unsupportedDevice
        }
        if let reason = availability.unavailableReason, !availability.isAvailableNow {
            throw AFMLLMClientError.unavailable(reason)
        }

        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS) || os(visionOS) || targetEnvironment(macCatalyst)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            _ = systemSessionBox()
            return
        }
        #endif
        #endif

        throw AFMLLMClientError.frameworkUnavailable
    }

    func syncSystemPrompt(_ prompt: String?) async {
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if systemPrompt != normalized {
            systemPrompt = normalized
            unload()
        }
    }

    func textStream(from input: LLMInput) async throws -> AsyncThrowingStream<String, Error> {
        try await load()
        let prompt = renderedPrompt(for: input)

        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS) || os(visionOS) || targetEnvironment(macCatalyst)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let activeSessionBox = systemSessionBox()
            return AsyncThrowingStream { continuation in
                Task {
                    await activeSessionBox.toolRecorder?.reset()
                    do {
                        let response = try await activeSessionBox.session.respond(to: prompt)
                        let summary = await activeSessionBox.toolRecorder?.drain()
                        if let summary {
                            await self.onToolSummary?(summary)
                        }
                        let output = Self.resolvedResponseText(
                            response: response,
                            transcriptResponseText: (summary?.isEmpty == false) ? activeSessionBox.lastTranscriptResponseText() : nil,
                            preferTranscriptFallback: summary?.isEmpty == false
                        )
                        for chunk in chunked(output) {
                            if Task.isCancelled { break }
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch {
                        if let summary = await activeSessionBox.toolRecorder?.drain() {
                            await self.onToolSummary?(summary)
                        }
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
        #endif
        #endif

        throw AFMLLMClientError.frameworkUnavailable
    }

    func unload() {
        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS) || os(visionOS) || targetEnvironment(macCatalyst)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            clearSystemSession()
        }
        #endif
        #endif
    }

    private func renderedPrompt(for input: LLMInput) -> String {
        switch input.content {
        case .plain(let text):
            return text
        case .messages(let messages):
            return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        case .multimodal(let text, _):
            return text
        case .multimodalMessages(let messages, _):
            return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        }
    }

    private func chunked(_ text: String, size: Int = 24) -> [String] {
        guard !text.isEmpty else { return [] }
        var chunks: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[index..<next]))
            index = next
        }
        return chunks
    }

    static func resolvedResponseText<T>(
        response: T,
        transcriptResponseText: String? = nil,
        preferTranscriptFallback: Bool = false
    ) -> String {
        let directText = extractResponseText(response)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !directText.isEmpty {
            return directText
        }

        if preferTranscriptFallback,
           let transcriptResponseText = transcriptResponseText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !transcriptResponseText.isEmpty {
            return transcriptResponseText
        }

        let fallback = String(describing: response).trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? directText : fallback
    }

    private static func extractResponseText<T>(_ response: T) -> String {
        let mirror = Mirror(reflecting: response)
        if let text = mirror.children.first(where: { $0.label == "content" })?.value as? String {
            return text
        }
        return ""
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func systemSessionBox() -> SessionBox {
        let signature = currentSessionSignature()
        if let box = sessionStorage as? SessionBox, box.signature == signature {
            return box
        }

        let toolRecorder = signature.toolAvailability.any ? AFMToolRecorder() : nil
        let session = makeSession(signature: signature, toolRecorder: toolRecorder)
        let box = SessionBox(session: session, signature: signature, toolRecorder: toolRecorder)
        sessionStorage = box
        return box
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func currentSessionSignature() -> SessionSignature {
        let toolAvailability = ToolAvailability.current(currentFormat: .afm)
        return SessionSignature(
            instructions: sessionInstructions(toolAvailability: toolAvailability) ?? "",
            toolAvailability: toolAvailability,
            guardrailsMode: guardrailsMode
        )
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func sessionInstructions(toolAvailability: ToolAvailability) -> String? {
        var merged = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if toolAvailability.any {
            SystemPromptResolver.appendToolGuidance(
                to: &merged,
                availability: toolAvailability,
                includeThinkRestriction: false
            )
        }
        let trimmed = merged.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func makeSession(signature: SessionSignature, toolRecorder: AFMToolRecorder?) -> LanguageModelSession {
        let model = SystemLanguageModel(guardrails: mappedGuardrails(for: signature.guardrailsMode))
        if signature.toolAvailability.any, let toolRecorder {
            var tools: [any FoundationModels.Tool] = []
            if signature.toolAvailability.webSearch {
                tools.append(AFMWebSearchTool(recorder: toolRecorder))
            }
            if signature.toolAvailability.python {
                tools.append(AFMPythonTool(recorder: toolRecorder))
            }
            if signature.toolAvailability.memory {
                tools.append(AFMMemoryTool(recorder: toolRecorder))
            }
            if signature.instructions.isEmpty {
                return LanguageModelSession(model: model, tools: tools)
            }
            return LanguageModelSession(model: model, tools: tools, instructions: signature.instructions)
        }

        if signature.instructions.isEmpty {
            return LanguageModelSession(model: model)
        }
        return LanguageModelSession(model: model, instructions: signature.instructions)
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func mappedGuardrails(for mode: AFMGuardrailsMode) -> SystemLanguageModel.Guardrails {
        switch mode {
        case .default:
            return .default
        case .permissiveContentTransformations:
            return .permissiveContentTransformations
        }
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func clearSystemSession() {
        sessionStorage = nil
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private struct SessionSignature: Equatable {
        let instructions: String
        let toolAvailability: ToolAvailability
        let guardrailsMode: AFMGuardrailsMode
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private final class SessionBox: @unchecked Sendable {
        let session: LanguageModelSession
        let signature: SessionSignature
        let toolRecorder: AFMToolRecorder?

        init(session: LanguageModelSession, signature: SessionSignature, toolRecorder: AFMToolRecorder?) {
            self.session = session
            self.signature = signature
            self.toolRecorder = toolRecorder
        }

        func lastTranscriptResponseText() -> String? {
            for entry in Array(session.transcript).reversed() {
                let mirror = Mirror(reflecting: entry)
                guard let child = mirror.children.first, child.label == "response" else { continue }
                let text = AFMLLMClient.extractResponseText(child.value)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
            return nil
        }
    }
    #endif
}
