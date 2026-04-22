// LeapLLMClient.swift
#if canImport(LeapSDK)
import Foundation
import LeapSDK
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public final actor LeapLLMClient {
    /// Wraps a ``ModelRunner`` so the runner can be safely transferred to this
    /// actor at initialization time. The box itself is annotated ``Sendable`` via
    /// ``@unchecked`` conformance since ``ModelRunner`` does not conform to
    /// ``Sendable``.
    private struct RunnerBox: @unchecked Sendable {
        let runner: any ModelRunner
    }

    /// Wraps a possibly non-`Sendable` message response stream so it can be
    /// safely captured by `@Sendable` closures.
    private struct MessageResponseStreamBox: @unchecked Sendable {
        let stream: AsyncThrowingStream<LeapSDK.MessageResponse, Error>
    }

    /// The underlying model runner. Access is always isolated to this actor to
    /// avoid data races.
    private let runnerBox: RunnerBox
    private var conversation: Conversation
    private var systemPrompt: String?
    private var didRegisterFunctions: Bool = false
    private var registeredToolAvailability: ToolAvailability = .none
    private let modelIdentifier: String?
    private var currentStreamTask: Task<Void, Never>?

    /// Internal initializer that receives a pre-wrapped ``RunnerBox``.
    /// This avoids cross-actor transfer of the non-``Sendable`` `ModelRunner`
    /// instance.
    private init(box: RunnerBox, systemPrompt: String?, modelIdentifier: String?) {
        self.runnerBox = box
        self.systemPrompt = systemPrompt
        self.modelIdentifier = modelIdentifier
        if let sp = systemPrompt, sp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let sys = LeapSDK.ChatMessage(role: .system, content: [LeapSDK.ChatMessageContent.text(sp)])
            self.conversation = Conversation(modelRunner: box.runner, history: [sys])
        } else {
            self.conversation = Conversation(modelRunner: box.runner, history: [])
        }
        // Register ET-only functions (e.g., web search) asynchronously to avoid
        // calling an actor-isolated method from the nonisolated initializer.
        Task { await self.registerFunctionsIfNeeded() }
    }

    /// Creates a client using the provided runner instance.
    /// - Parameter runner: The runner capable of executing ET models.
    ///   This factory is annotated with `@preconcurrency` so callers from
    ///   Swift Concurrency contexts can pass in the non-``Sendable`` runner.
    @preconcurrency
    public static func make(runner: any ModelRunner) -> LeapLLMClient { LeapLLMClient(box: RunnerBox(runner: runner), systemPrompt: nil, modelIdentifier: nil) }

    /// Creates a client and initializes the conversation with a system prompt.
    @preconcurrency
    public static func make(runner: any ModelRunner, systemPrompt: String?) -> LeapLLMClient {
        return LeapLLMClient(box: RunnerBox(runner: runner), systemPrompt: systemPrompt, modelIdentifier: nil)
    }

    /// Creates a client with an optional model identifier for parser selection.
    @preconcurrency
    public static func make(runner: any ModelRunner, systemPrompt: String?, modelIdentifier: String?) -> LeapLLMClient {
        return LeapLLMClient(box: RunnerBox(runner: runner), systemPrompt: systemPrompt, modelIdentifier: modelIdentifier)
    }

    /// Creates a client with an optional model identifier for parser selection.
    @preconcurrency
    public static func make(runner: any ModelRunner, modelIdentifier: String?) -> LeapLLMClient {
        return LeapLLMClient(box: RunnerBox(runner: runner), systemPrompt: nil, modelIdentifier: modelIdentifier)
    }

    private func ensureConversation() async -> Conversation { conversation }

    // Track the currently running stream task so callers can cancel promptly.
    private func setCurrentTask(_ task: Task<Void, Never>?) {
        currentStreamTask = task
    }

    public func cancelActive() {
        currentStreamTask?.cancel()
    }
    // Reset-related helpers removed; conversation persists across turns.

    /// Hard-reset the underlying Conversation to clear any transient cancellation
    /// state after an interrupted prefill or function-call stop. Re-applies the
    /// current system prompt (if any) and re-registers functions when armed.
    public func hardResetConversation() {
        if let sp = systemPrompt, sp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let sys = LeapSDK.ChatMessage(role: .system, content: [LeapSDK.ChatMessageContent.text(sp)])
            self.conversation = Conversation(modelRunner: runnerBox.runner, history: [sys])
        } else {
            self.conversation = Conversation(modelRunner: runnerBox.runner, history: [])
        }
        didRegisterFunctions = false
        registeredToolAvailability = .none
        registerFunctionsIfNeeded()
    }

    /// Replaces the current conversation with a new one that includes the provided system prompt.
    public func setSystemPrompt(_ prompt: String?) {
        systemPrompt = prompt
        if let sp = prompt, sp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let sys = LeapSDK.ChatMessage(role: .system, content: [LeapSDK.ChatMessageContent.text(sp)])
            conversation = Conversation(modelRunner: runnerBox.runner, history: [sys])
        } else {
            conversation = Conversation(modelRunner: runnerBox.runner, history: [])
        }
        didRegisterFunctions = false
        registeredToolAvailability = .none
        registerFunctionsIfNeeded()
    }

    /// Updates the system prompt while preserving existing non-system history.
    /// This allows dynamic prompt changes (e.g., web-search armed state) without
    /// resetting the ongoing conversation context.
    public func syncSystemPrompt(_ prompt: String?) {
        let normalized: String? = {
            guard let p = prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !p.isEmpty else { return nil }
            return p
        }()
        let currentNormalized: String? = {
            guard let p = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !p.isEmpty else { return nil }
            return p
        }()
        let desiredToolAvailability = ToolAvailability.current(currentFormat: .et)
        if normalized == currentNormalized, desiredToolAvailability == registeredToolAvailability {
            if desiredToolAvailability.any && !didRegisterFunctions {
                registerFunctionsIfNeeded()
            }
            return
        }

        var nonSystemHistory: [LeapSDK.ChatMessage] = []
        nonSystemHistory.reserveCapacity(conversation.history.count)
        for message in conversation.history {
            switch message.role {
            case .system:
                continue
            default:
                nonSystemHistory.append(message)
            }
        }

        if let sp = normalized {
            let sys = LeapSDK.ChatMessage(role: .system, content: [LeapSDK.ChatMessageContent.text(sp)])
            conversation = runnerBox.runner.createConversationFromHistory(history: [sys] + nonSystemHistory)
            systemPrompt = sp
        } else {
            conversation = runnerBox.runner.createConversationFromHistory(history: nonSystemHistory)
            systemPrompt = nil
        }
        didRegisterFunctions = false
        registeredToolAvailability = .none
        registerFunctionsIfNeeded()
    }

    public func textStream(from input: LLMInput) async throws -> AsyncThrowingStream<String, Error> {
        try await responseTokenStream(for: input)
    }

    // Select a function-call parser based on model identifier (e.g., Qwen/Hermes vs LFM).
    // Qwen-3 and Hermes-style models emit function calls in a different format
    // than LFM2. The Leap Edge SDK provides a HermesFunctionCallParser for this.
    // If an unknown model is used, we fall back to the default LFM parser by
    // not overriding GenerationOptions.functionCallParser.
    private func applyFunctionCallParserSelection(to options: inout GenerationOptions) {
        let ident = (modelIdentifier ?? "").lowercased()
        // Use Hermes-style parser for Qwen-family models or explicit Hermes builds
        let useHermes = ident.contains("qwen") || ident.contains("hermes")
        if useHermes {
            // Note: HermesFunctionCallParser is available in LeapSDK v0.5.0+.
            // If building with an older SDK, update the dependency.
            options.functionCallParser = HermesFunctionCallParser()
        }
    }

    private func normalizedToolName(_ rawName: String) -> String {
        if rawName == "noema.web.retrieve" { return "noema.web.retrieve" }
        if rawName == "noema_web_retrieve" { return "noema.web.retrieve" }
        if rawName == "Web_Search" || rawName == "WEB_SEARCH" { return "noema.web.retrieve" }
        if rawName == "noema.python.execute" { return "noema.python.execute" }
        if rawName == "noema_python_execute" { return "noema.python.execute" }
        if rawName == "noema.memory" { return "noema.memory" }
        if rawName == "noema_memory" { return "noema.memory" }
        let lower = rawName.lowercased()
        if lower == "web_search" || lower == "web.search" || lower == "websearch" || lower == "web-search" {
            return "noema.web.retrieve"
        }
        if lower == "python" || lower == "python_execute" || lower == "code_execute"
            || lower == "run_python" || lower == "execute_python" || lower == "python.execute"
            || lower == "code_interpreter" || lower == "code-interpreter" {
            return "noema.python.execute"
        }
        if lower == "memory" || lower == "memory_tool" || lower == "memorytool"
            || lower == "persistent_memory" || lower == "persistent-memory" {
            return "noema.memory"
        }
        return rawName
    }

    private func toolPayloadJSON(from call: LeapFunctionCall) -> String {
        let toolName = normalizedToolName(call.name)
        let argsNoNil: [String: Any] = call.arguments.reduce(into: [:]) { acc, pair in
            if let v = pair.value { acc[pair.key] = v }
        }
        let payload: [String: Any] = ["tool": toolName, "args": argsNoNil]
        let data = try? JSONSerialization.data(withJSONObject: payload)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"tool\":\"\(toolName)\",\"args\":{}}"
    }

    private func leapMessage(from message: ChatMessage) -> LeapSDK.ChatMessage {
        let roleLower = message.role.lowercased()
        let content = [LeapSDK.ChatMessageContent.text(message.content)]
        if roleLower == "user" || roleLower == "🧑‍💻".lowercased() {
            return LeapSDK.ChatMessage(role: .user, content: content)
        }
        if roleLower == "assistant" || roleLower == "🤖".lowercased() {
            return LeapSDK.ChatMessage(role: .assistant, content: content)
        }
        if roleLower == "tool" {
            return LeapSDK.ChatMessage(role: .tool, content: content)
        }
        if roleLower == "system" {
            return LeapSDK.ChatMessage(role: .system, content: content)
        }
        return LeapSDK.ChatMessage(role: .user, content: content)
    }

    // Streaming wrapper over `LeapSDK` conversation streaming. Supports plain, messages, and multimodal.
    private func responseTokenStream(for input: LLMInput) async throws -> AsyncThrowingStream<String, Error> {
        var conv = await ensureConversation()
        // Ensure functions are registered on the exact Conversation instance we're about to use.
        // Do this synchronously to prevent a race where the first tool call occurs before
        // the Leap SDK sees the registrations, which can surface as LeapError error 2.
        self.registerFunctionsIfNeeded()
        var options = GenerationOptions()
        // Choose the correct function-call parser for this model (e.g., Hermes for Qwen3)
        applyFunctionCallParserSelection(to: &options)
        let stream: AsyncThrowingStream<LeapSDK.MessageResponse, Error>
        var usedImages = false
        switch input.content {
        case .plain(let t):
            stream = conv.generateResponse(userTextMessage: t, generationOptions: options)
        case .messages(let msgs):
            guard !msgs.isEmpty else {
                stream = conv.generateResponse(userTextMessage: "", generationOptions: options)
                break
            }
            let mapped = msgs.map(leapMessage(from:))
            if mapped.count > 1 {
                let appendedHistory = conv.history + Array(mapped.dropLast())
                conv = runnerBox.runner.createConversationFromHistory(history: appendedHistory)
                conversation = conv
                didRegisterFunctions = false
                registerFunctionsIfNeeded()
            }
            guard let last = mapped.last else {
                stream = conv.generateResponse(userTextMessage: "", generationOptions: options)
                break
            }
            stream = conv.generateResponse(message: last, generationOptions: options)
        case .multimodal(let text, let imagePaths):
            // Ensure we only pass images to a vision-capable Leap model
            let modelSupportsVision: Bool = {
                if let ident = modelIdentifier { return LeapCatalogService.isVisionQuantizationSlug(ident) }
                return false
            }()
            // Build a mixed-content message with user text followed by JPEG image parts.
            var imageParts: [LeapSDK.ChatMessageContent] = []
            var attachedAnyImage = false
            for path in imagePaths.prefix(5) {
                let url = URL(fileURLWithPath: path)
                if let raw = try? Data(contentsOf: url) {
                    // Prefer SDK helpers to construct image content in JPEG format
                    #if canImport(UIKit)
                    if let ui = UIImage(data: raw), let part = try? LeapSDK.ChatMessageContent.fromUIImage(ui, compressionQuality: 0.85) {
                        imageParts.append(part)
                        attachedAnyImage = true
                        continue
                    }
                    #elseif canImport(AppKit)
                    if let ns = NSImage(data: raw), let part = try? LeapSDK.ChatMessageContent.fromNSImage(ns, compressionQuality: 0.85) {
                        imageParts.append(part)
                        attachedAnyImage = true
                        continue
                    }
                    #endif
                    if let jpeg = Self.convertToJPEGData(raw) {
                        imageParts.append(LeapSDK.ChatMessageContent.fromJPEGData(jpeg))
                        attachedAnyImage = true
                    }
                }
            }
            usedImages = attachedAnyImage
            if attachedAnyImage && !modelSupportsVision {
                let friendly = NSError(
                    domain: "Leap",
                    code: -10091,
                    userInfo: [NSLocalizedDescriptionKey: "This ET model is not vision-capable. Select a Vision bundle and try again."]
                )
                stream = AsyncThrowingStream<LeapSDK.MessageResponse, Error> { continuation in
                    continuation.finish(throwing: friendly)
                }
            } else {
                // Attach text first, then image in the same user message
                let message = LeapSDK.ChatMessage(role: .user, content: [LeapSDK.ChatMessageContent.text(text)] + imageParts)
                #if DEBUG
                let partKinds = message.content.map { part -> String in
                    switch part {
                    case .text(_): return "text"
                    case .image(_): return "image"
                    @unknown default: return "unknown"
                    }
                }
                await logger.log("[Leap] Sending message parts: \(message.content.count) [\(partKinds.joined(separator: ","))]")
                #endif
                stream = conv.generateResponse(message: message, generationOptions: options)
            }
        case .multimodalMessages(let messages, let imagePaths):
            let text = messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            // Ensure we only pass images to a vision-capable Leap model
            let modelSupportsVision: Bool = {
                if let ident = modelIdentifier { return LeapCatalogService.isVisionQuantizationSlug(ident) }
                return false
            }()
            var imageParts: [LeapSDK.ChatMessageContent] = []
            var attachedAnyImage = false
            for path in imagePaths.prefix(5) {
                let url = URL(fileURLWithPath: path)
                if let raw = try? Data(contentsOf: url) {
                    #if canImport(UIKit)
                    if let ui = UIImage(data: raw), let part = try? LeapSDK.ChatMessageContent.fromUIImage(ui, compressionQuality: 0.85) {
                        imageParts.append(part)
                        attachedAnyImage = true
                        continue
                    }
                    #elseif canImport(AppKit)
                    if let ns = NSImage(data: raw), let part = try? LeapSDK.ChatMessageContent.fromNSImage(ns, compressionQuality: 0.85) {
                        imageParts.append(part)
                        attachedAnyImage = true
                        continue
                    }
                    #endif
                    if let jpeg = Self.convertToJPEGData(raw) {
                        imageParts.append(LeapSDK.ChatMessageContent.fromJPEGData(jpeg))
                        attachedAnyImage = true
                    }
                }
            }
            usedImages = attachedAnyImage
            if attachedAnyImage && !modelSupportsVision {
                let friendly = NSError(
                    domain: "Leap",
                    code: -10091,
                    userInfo: [NSLocalizedDescriptionKey: "This ET model is not vision-capable. Select a Vision bundle and try again."]
                )
                stream = AsyncThrowingStream<LeapSDK.MessageResponse, Error> { continuation in
                    continuation.finish(throwing: friendly)
                }
            } else {
                let message = LeapSDK.ChatMessage(role: .user, content: [LeapSDK.ChatMessageContent.text(text)] + imageParts)
                #if DEBUG
                let partKinds = message.content.map { part -> String in
                    switch part {
                    case .text(_): return "text"
                    case .image(_): return "image"
                    @unknown default: return "unknown"
                    }
                }
                await logger.log("[Leap] Sending message parts: \(message.content.count) [\(partKinds.joined(separator: ","))]")
                #endif
                stream = conv.generateResponse(message: message, generationOptions: options)
            }
        }
        let streamBox = MessageResponseStreamBox(stream: stream)
        return AsyncThrowingStream<String, Error>(bufferingPolicy: .unbounded) { continuation in
            let produceTask = Task { [streamBox, usedImages] in
                let base = streamBox.stream
                do {
                    var emittedThinkOpen = false
                    for try await response in base {
                        switch response {
                        case .chunk(let token):
                            // Flush any pending think close to isolate reasoning from final text stream
                            if emittedThinkOpen {
                                continuation.yield("</think>")
                                emittedThinkOpen = false
                            }
                            continuation.yield(token)
                        case .reasoningChunk(let chunk):
                            if !emittedThinkOpen {
                                continuation.yield("<think>")
                                emittedThinkOpen = true
                            }
                            continuation.yield(chunk)
                        case .functionCall(let calls):
                            // Close any open think block before emitting tool signal
                            if emittedThinkOpen {
                                continuation.yield("</think>")
                                emittedThinkOpen = false
                            }
                            for call in calls {
                                continuation.yield("TOOL_CALL: \(toolPayloadJSON(from: call))")
                            }
                            // Finish this stream so the higher-level ChatVM can execute the tool
                            // and then append a tool response message on the SAME Conversation.
                            continuation.finish()
                            return
                        case .complete(let completion):
                            if emittedThinkOpen {
                                continuation.yield("</think>")
                                emittedThinkOpen = false
                            }
                            if let calls = completion.message.functionCalls, !calls.isEmpty {
                                for call in calls {
                                    continuation.yield("TOOL_CALL: \(toolPayloadJSON(from: call))")
                                }
                                continuation.finish()
                                return
                            }
                            break
                        @unknown default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    #if DEBUG
                    await logger.log("[Leap] Generation error: \(String(describing: error))")
                    if let leapErr = error as? LeapSDK.LeapError {
                        switch leapErr {
                        case .generationFailure:
                            await logger.log("[Leap] Detected generationFailure (LeapError 2). This often indicates an unresolved or ambiguous function call or a tool exception.")
                        default:
                            break
                        }
                    } else {
                        let ns = error as NSError
                        if ns.code == 2 {
                            await logger.log("[Leap] Detected Leap error code 2 (generationFailure). Ensure only the canonical 'noema.web.retrieve' is registered and aliases like 'web_search' are not registered.")
                        }
                    }
                    #endif
                    if usedImages {
                        let friendly = NSError(
                            domain: "Leap",
                            code: -10090,
                            userInfo: [
                                NSLocalizedDescriptionKey: "This ET model cannot process images (vision not supported).",
                                NSUnderlyingErrorKey: error
                            ]
                        )
                        continuation.finish(throwing: friendly)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            // Propagate consumer cancellation to the underlying Leap conversation stream
            Task { await self.setCurrentTask(produceTask) }
            continuation.onTermination = { [weak self, produceTask] _ in
                produceTask.cancel()
                Task { await self?.setCurrentTask(nil) }
            }
        }
    }

    // MARK: - ET-only function registration (Leap Edge SDK)
    private func registerFunctionsIfNeeded() {
        let availability = ToolAvailability.current(currentFormat: .et)
        guard availability.any else {
            didRegisterFunctions = false
            registeredToolAvailability = .none
            return
        }
        guard didRegisterFunctions == false || registeredToolAvailability != availability else { return }

        if availability.webSearch {
            let webParams: [LeapFunctionParameter] = [
                LeapFunctionParameter(
                    name: "query",
                    type: .string(StringType()),
                    description: "Search query string",
                    optional: false
                ),
                LeapFunctionParameter(
                    name: "count",
                    type: .integer(IntegerType()),
                    description: "Number of results to return (1-5). Default: 3",
                    optional: true
                ),
                LeapFunctionParameter(
                    name: "safesearch",
                    type: .string(StringType(enumValues: ["off", "moderate", "strict"])),
                    description: "Safe search level (off, moderate, strict). Default: moderate",
                    optional: true
                )
            ]

            // Register underscore-safe name for Leap parser; normalize back to dotted at runtime
            let webUnderscore = LeapFunction(
                name: "noema_web_retrieve",
                description: "Web search via SearXNG; returns web results (title, url, snippet).",
                parameters: webParams
            )
            conversation.registerFunction(webUnderscore)
        }

        if availability.python {
            let pythonFunction = LeapFunction(
                name: "noema_python_execute",
                description: "Execute Python 3 code for calculations, data processing, parsing, and other computational work. Use print() to return values.",
                parameters: [
                    LeapFunctionParameter(
                        name: "code",
                        type: .string(StringType()),
                        description: "Runnable Python 3 code. Use print() to produce output.",
                        optional: false
                    )
                ]
            )
            conversation.registerFunction(pythonFunction)
        }

        if availability.memory {
            let memoryFunction = LeapFunction(
                name: "noema_memory",
                description: "Read or update persistent on-device memory entries that remain available across conversations.",
                parameters: [
                    LeapFunctionParameter(
                        name: "operation",
                        type: .string(StringType(enumValues: ["list", "view", "create", "replace", "insert", "str_replace", "delete", "rename"])),
                        description: "Memory operation to perform.",
                        optional: false
                    ),
                    LeapFunctionParameter(
                        name: "entry_id",
                        type: .string(StringType()),
                        description: "Stable entry id for an existing memory.",
                        optional: true
                    ),
                    LeapFunctionParameter(
                        name: "title",
                        type: .string(StringType()),
                        description: "Memory title. Required for create and may identify an existing memory when entry_id is omitted.",
                        optional: true
                    ),
                    LeapFunctionParameter(
                        name: "content",
                        type: .string(StringType()),
                        description: "Memory content. Required for create, replace, and insert.",
                        optional: true
                    ),
                    LeapFunctionParameter(
                        name: "old_string",
                        type: .string(StringType()),
                        description: "Existing text to replace for str_replace.",
                        optional: true
                    ),
                    LeapFunctionParameter(
                        name: "new_string",
                        type: .string(StringType()),
                        description: "Replacement text for str_replace, or the new title for rename.",
                        optional: true
                    ),
                    LeapFunctionParameter(
                        name: "insert_at",
                        type: .integer(IntegerType()),
                        description: "Character offset for insert. Omit to append at the end.",
                        optional: true
                    )
                ]
            )
            conversation.registerFunction(memoryFunction)
        }

        didRegisterFunctions = true
        registeredToolAvailability = availability
    }

    // MARK: - Image helpers
    /// Convert arbitrary image data to JPEG Data suitable for Leap Edge `.image(Data)`
    private static func convertToJPEGData(_ data: Data, maxSide: CGFloat = 1280, quality: CGFloat = 0.85) -> Data? {
        #if canImport(UIKit)
        guard let img = UIImage(data: data) else { return nil }
        let scaled = resizeUIImage(img, maxSide: maxSide)
        return scaled.jpegData(compressionQuality: quality)
        #elseif canImport(AppKit)
        guard let ns = NSImage(data: data) else { return nil }
        let scaled = resizeNSImage(ns, maxSide: maxSide)
        guard let tiff = scaled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else { return nil }
        return jpeg
        #else
        // If no platform image framework, pass-through and hope it's already JPEG
        return data
        #endif
    }
    #if canImport(UIKit)
    private static func resizeUIImage(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let s = max(image.size.width, image.size.height)
        guard s > maxSide else { return image }
        let scale = maxSide / s
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out ?? image
    }
    #elseif canImport(AppKit)
    private static func resizeNSImage(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
        let w = CGFloat(rep?.pixelsWide ?? Int(image.size.width))
        let h = CGFloat(rep?.pixelsHigh ?? Int(image.size.height))
        let s = max(w, h)
        guard s > maxSide else { return image }
        let scale = maxSide / s
        let newSize = NSSize(width: w * scale, height: h * scale)
        let out = NSImage(size: newSize)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        out.unlockFocus()
        return out
    }
    #endif
}

#endif
