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
        // Register SLM-only functions (e.g., web search) asynchronously to avoid
        // calling an actor-isolated method from the nonisolated initializer.
        Task { await self.registerFunctionsIfNeeded() }
    }

    /// Creates a client using the provided runner instance.
    /// - Parameter runner: The runner capable of executing SLM models.
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

    // Streaming wrapper over `LeapSDK` conversation streaming. Supports plain, messages, and multimodal.
    private func responseTokenStream(for input: LLMInput) async throws -> AsyncThrowingStream<String, Error> {
        let conv = await ensureConversation()
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
            // Build a single Leap message. If a tool result is included alongside a user nudge
            // (e.g., [tool, user]), combine them into one user message with two parts so the
            // existing Conversation sees both in a single turn.
            guard let last = msgs.last else {
                stream = conv.generateResponse(userTextMessage: "", generationOptions: options)
                break
            }
            let roleLower = last.role.lowercased()
            let contentText = last.content
            // Detect adjacent tool result preceding the last message
            let prevToolContent: String? = {
                if msgs.count >= 2 {
                    let prev = msgs[msgs.count - 2]
                    if prev.role.lowercased() == "tool" { return prev.content }
                }
                // Also consider any earlier tool message if not immediately adjacent
                return msgs.last(where: { $0.role.lowercased() == "tool" })?.content
            }()
            let leapMessage: LeapSDK.ChatMessage = {
                if roleLower == "user" || roleLower == "🧑‍💻".lowercased() {
                    if let toolJSON = prevToolContent {
                        let wrapped = "<tool_response>\n" + toolJSON + "\n</tool_response>"
                        return LeapSDK.ChatMessage(
                            role: .user,
                            content: [
                                LeapSDK.ChatMessageContent.text(wrapped),
                                LeapSDK.ChatMessageContent.text(contentText)
                            ]
                        )
                    }
                    return LeapSDK.ChatMessage(role: .user, content: [LeapSDK.ChatMessageContent.text(contentText)])
                } else if roleLower == "assistant" || roleLower == "🤖".lowercased() {
                    return LeapSDK.ChatMessage(role: .assistant, content: [LeapSDK.ChatMessageContent.text(contentText)])
                } else if roleLower == "tool" {
                    let wrapped = "<tool_response>\n" + contentText + "\n</tool_response>"
                    return LeapSDK.ChatMessage(role: .user, content: [LeapSDK.ChatMessageContent.text(wrapped)])
                } else if roleLower == "system" {
                    return LeapSDK.ChatMessage(role: .system, content: [LeapSDK.ChatMessageContent.text(contentText)])
                } else {
                    return LeapSDK.ChatMessage(role: .user, content: [LeapSDK.ChatMessageContent.text(contentText)])
                }
            }()
            stream = conv.generateResponse(message: leapMessage, generationOptions: options)
        case .multimodal(let text, let imagePaths):
            // Ensure we only pass images to a vision-capable Leap model
            let modelSupportsVision: Bool = {
                if let ident = modelIdentifier { return LeapCatalogService.isVisionQuantizationSlug(ident) }
                return false
            }()
            // Build a mixed-content message with user text followed by at most one JPEG image.
            // Some Leap EDGE runners expect text first; multiple images may not be supported.
            var imageParts: [LeapSDK.ChatMessageContent] = []
            var attachedAnyImage = false
            for path in imagePaths {
                let url = URL(fileURLWithPath: path)
                if let raw = try? Data(contentsOf: url) {
                    // Prefer SDK helpers to construct image content in JPEG format
                    #if canImport(UIKit)
                    if let ui = UIImage(data: raw), let part = try? LeapSDK.ChatMessageContent.fromUIImage(ui, compressionQuality: 0.85) {
                        imageParts.append(part)
                        attachedAnyImage = true
                        break
                    }
                    #elseif canImport(AppKit)
                    if let ns = NSImage(data: raw), let part = try? LeapSDK.ChatMessageContent.fromNSImage(ns, compressionQuality: 0.85) {
                        imageParts.append(part)
                        attachedAnyImage = true
                        break
                    }
                    #endif
                    if let jpeg = Self.convertToJPEGData(raw) {
                        imageParts.append(LeapSDK.ChatMessageContent.fromJPEGData(jpeg))
                        attachedAnyImage = true
                        break
                    }
                }
            }
            usedImages = attachedAnyImage
            if attachedAnyImage && !modelSupportsVision {
                let friendly = NSError(
                    domain: "Leap",
                    code: -10091,
                    userInfo: [NSLocalizedDescriptionKey: "This SLM model is not vision-capable. Select a Vision bundle and try again."]
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
                            // Emit a TOOL_CALL token so existing middleware executes tools and restarts
                            for call in calls {
                                // Normalize tool name to our registry naming if needed
                                let rawName = call.name
                                let toolName: String = {
                                    // Canonicalize to our registered tool name
                                    if rawName == "noema.web.retrieve" { return "noema.web.retrieve" }
                                    if rawName == "noema_web_retrieve" { return "noema.web.retrieve" }
                                    if rawName == "Web_Search" || rawName == "WEB_SEARCH" { return "noema.web.retrieve" }
                                    // Normalize common Leap/SLM aliases
                                    let lower = rawName.lowercased()
                                    if lower == "web_search" || lower == "web.search" || lower == "websearch" || lower == "web-search" {
                                        return "noema.web.retrieve"
                                    }
                                    // Fallback to rawName if we don't recognize it
                                    return rawName
                                }()
                                // Remove nils from arguments for JSON serialization
                                let argsNoNil: [String: Any] = call.arguments.reduce(into: [:]) { acc, pair in
                                    if let v = pair.value { acc[pair.key] = v }
                                }
                                var payload: [String: Any] = [
                                    "tool": toolName,
                                    "args": argsNoNil
                                ]
                                // Best-effort JSON encoding
                                let data = (try? JSONSerialization.data(withJSONObject: payload))
                                let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"tool\":\"\(toolName)\",\"args\":{}}"
                                continuation.yield("TOOL_CALL: \(json)")
                            }
                            // Finish this stream so the higher-level ChatVM can execute the tool
                            // and then append a tool response message on the SAME Conversation.
                            continuation.finish()
                            return
                        case .complete:
                            if emittedThinkOpen {
                                continuation.yield("</think>")
                                emittedThinkOpen = false
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
                                NSLocalizedDescriptionKey: "This SLM model cannot process images (vision not supported).",
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

    // MARK: - SLM-only function registration (Leap Edge SDK)
    private func registerFunctionsIfNeeded() {
        // Only register the canonical function when the web search is ARMED.
        // Do not register aliases. Avoid exposing tools when not armed.
        guard didRegisterFunctions == false else { return }
        let armed = UserDefaults.standard.object(forKey: "webSearchArmed") as? Bool ?? false
        guard armed else { return }

        // Define the web search function in Leap SDK schema (canonical only)
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

        didRegisterFunctions = true
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
