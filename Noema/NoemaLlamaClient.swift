// NoemaLlamaClient.swift
// NoemaLlamaClient.swift - Swift wrapper for our llama.cpp implementation

import Foundation

// MARK: - Errors

enum NoemaLlamaError: Error, LocalizedError {
    case modelLoadFailed
    case contextCreationFailed
    case samplerCreationFailed
    case generationFailed
    case invalidParameters
    
    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: return "Failed to load model"
        case .contextCreationFailed: return "Failed to create context"
        case .samplerCreationFailed: return "Failed to create sampler"
        case .generationFailed: return "Text generation failed"
        case .invalidParameters: return "Invalid parameters"
        }
    }
}

// MARK: - Vision configuration
public enum LlamaVisionMode: Sendable {
    case auto
    case mergedOnly
    case projectorRequired
}

// MARK: - LLM Input/Output Types

public struct LLMInput: Sendable {
    public enum Content: Sendable {
        case plain(String)
        case messages([ChatMessage])
        case multimodal(text: String, imagePaths: [String])
    }
    
    public let content: Content
    
    public init(_ content: Content) {
        self.content = content
    }
    
    var prompt: String {
        switch content {
        case .plain(let text):
            return text
        case .messages(let messages):
            return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        case .multimodal(let text, _):
            // For llama.cpp we inject an image placeholder token per image; adapters will handle real images
            return text
        }
    }
}

public extension LLMInput {
    static func plain(_ text: String) -> LLMInput { LLMInput(.plain(text)) }
    static func multimodal(text: String, imagePaths: [String]) -> LLMInput { LLMInput(.multimodal(text: text, imagePaths: imagePaths)) }
}

public struct ChatMessage: Sendable {
    public let role: String
    public let content: String
    
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - NoemaLlamaClient

public final class NoemaLlamaClient: @unchecked Sendable {
    private var runner: LlamaRunner?
    private let modelURL: URL
    private let temperature: Float
    private let topP: Float
    private let topK: Int32
    private let contextLength: Int32
    private let visionMode: LlamaVisionMode
    private let mmprojPath: String?
    // Capability flag for vision-enabled builds; set dynamically on load
    private var visionImagesSupported: Bool = false
    
    public init(
        url: URL,
        contextLength: Int32 = 2048,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int32 = 40,
        visionMode: LlamaVisionMode = .auto,
        mmprojPath: String? = nil
    ) {
        self.modelURL = url
        self.contextLength = contextLength
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.visionMode = visionMode
        self.mmprojPath = mmprojPath
    }
    
    deinit {
        unload()
    }
    
    // MARK: - Loading/Unloading
    
    public func load() async throws {
        try await Task.detached { [weak self] in
            guard let self else { return }
            guard FileManager.default.fileExists(atPath: self.modelURL.path) else {
                throw NoemaLlamaError.invalidParameters
            }
            // Respect environment-provided tuning from the app (ChatVM.applyEnvironmentVariables)
            func intEnv(_ key: String) -> Int32? {
                guard let c = getenv(key) else { return nil }
                return Int32(String(cString: c))
            }
            let threadsEnv = intEnv("LLAMA_THREADS")
            let gpuLayersEnv = intEnv("LLAMA_N_GPU_LAYERS")
            let ctxEnv = intEnv("LLAMA_CONTEXT_SIZE")

            let fallbackThreadCount = Int32(max(2, Int(ProcessInfo.processInfo.processorCount - 2)))
            let threadsValue = threadsEnv.flatMap { $0 > 0 ? $0 : nil } ?? fallbackThreadCount
            let threads = max(Int32(2), threadsValue)

            #if canImport(Metal)
            let defaultGpuLayers: Int32 = 1_000_000
            #else
            let defaultGpuLayers: Int32 = 0
            #endif

            let nGpuLayers: Int32 = {
                if DeviceGPUInfo.supportsGPUOffload {
                    return gpuLayersEnv ?? defaultGpuLayers
                }
                return 0
            }()

            // If images will be used in this process, prefer a generous context
            let requestedCtx = ctxEnv ?? self.contextLength
            let envVerbose = (getenv("NOEMA_LLAMA_VERBOSE") != nil)
            let nCtx: Int32 = {
                if envVerbose { return max(requestedCtx, 8192) }
                return requestedCtx
            }()

            // Validate projector if provided: exists and quant family aligns with base
            var projectorPathToUse: String? = nil
            if let mm = self.mmprojPath, !mm.isEmpty {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: mm, isDirectory: &isDir), !isDir.boolValue {
                    // Compare quant family tokens (e.g., Q4_K_M vs F16)
                    let baseLabel = QuantExtractor.shortLabel(from: self.modelURL.lastPathComponent, format: .gguf)
                    let projLabel = QuantExtractor.shortLabel(from: URL(fileURLWithPath: mm).lastPathComponent, format: .gguf)
                    // Accept F16/F32 projectors for any base, or exact family match otherwise
                    let normalizedProj = projLabel.uppercased()
                    if normalizedProj.contains("F16") || normalizedProj.contains("F32") || normalizedProj == baseLabel.uppercased() {
                        projectorPathToUse = mm
                    } else {
                        if envVerbose { fputs("[NoemaLlamaClient] Projector quant (\(projLabel)) mismatches base (\(baseLabel)).\n", stderr) }
                        // Leave nil to run merged-only mode
                    }
                } else {
                    if envVerbose { fputs("[NoemaLlamaClient] Projector file missing: \(mm)\n", stderr) }
                }
            }

            // If no explicit projector provided and GGUF lacks an integrated projector, try auto-discovery
            if projectorPathToUse == nil {
                let hasMergedVision = GGUFMetadata.hasMultimodalProjector(at: self.modelURL)
                if hasMergedVision == false {
                    // 1) artifacts.json hint next to weights
                    let dir = self.modelURL.deletingLastPathComponent()
                    let artifactsURL = dir.appendingPathComponent("artifacts.json")
                    if let data = try? Data(contentsOf: artifactsURL),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let mmRel = obj["mmproj"] as? String {
                        let cand = dir.appendingPathComponent(mmRel)
                        if FileManager.default.fileExists(atPath: cand.path) {
                            projectorPathToUse = cand.path
                        }
                    }
                    // 2) filename heuristics in the same directory
                    if projectorPathToUse == nil {
                        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                            let baseLabel = QuantExtractor.shortLabel(from: self.modelURL.lastPathComponent, format: .gguf).uppercased()
                            let isMMProjName: (String) -> Bool = { name in
                                let lower = name.lowercased()
                                return lower.contains("mmproj") || lower.contains("projector") || lower.contains("image_proj")
                            }
                            // Prefer F16/F32 projectors first, else exact quant family match
                            let ggufs = files.filter { $0.pathExtension.lowercased() == "gguf" && isMMProjName($0.lastPathComponent) }
                            let f16First = ggufs.first(where: { QuantExtractor.shortLabel(from: $0.lastPathComponent, format: .gguf).uppercased().contains("F16") || QuantExtractor.shortLabel(from: $0.lastPathComponent, format: .gguf).uppercased().contains("F32") })
                            let familyMatch = ggufs.first(where: { QuantExtractor.shortLabel(from: $0.lastPathComponent, format: .gguf).uppercased() == baseLabel })
                            if let pick = f16First ?? familyMatch, FileManager.default.fileExists(atPath: pick.path) {
                                projectorPathToUse = pick.path
                                if envVerbose { fputs("[NoemaLlamaClient] Auto-detected projector: \(pick.lastPathComponent)\n", stderr) }
                            } else if envVerbose {
                                fputs("[NoemaLlamaClient] No projector found next to weights; vision will be disabled if the model requires one.\n", stderr)
                            }
                        }
                    }
                }
            }

            if let projectorPathToUse {
                self.runner = LlamaRunner(
                    modelPath: self.modelURL.path,
                    mmprojPath: projectorPathToUse,
                    nCtxTokens: nCtx,
                    nGpuLayers: nGpuLayers,
                    nThreads: threads
                )
            } else {
                self.runner = LlamaRunner(
                    modelPath: self.modelURL.path,
                    nCtxTokens: nCtx,
                    nGpuLayers: nGpuLayers,
                    nThreads: threads
                )
            }
            if self.runner == nil { throw NoemaLlamaError.modelLoadFailed }
            // Detect compile-time vision capability
            self.visionImagesSupported = self.runner?.hasVisionOps() ?? false
            if self.visionImagesSupported {
                // Runtime probe to distinguish between compiled-with-vision vs model missing projector
                let probe = self.runner?.probeVision() ?? .unavailable
                switch self.visionMode {
                case .mergedOnly:
                    if probe != .OK { self.visionImagesSupported = false }
                case .projectorRequired:
                    self.visionImagesSupported = (probe == .OK)
                case .auto:
                    // In auto mode, disable images unless probe succeeds
                    self.visionImagesSupported = (probe == .OK)
                }
                if envVerbose {
                    if self.visionImagesSupported {
                        fputs("[NoemaLlamaClient] Vision enabled with mode=\(self.visionMode).\n", stderr)
                    } else {
                        fputs("[NoemaLlamaClient] Vision disabled with mode=\(self.visionMode).\n", stderr)
                    }
                }
            }
        }.value
    }
    
    public func unload() {
        runner?.unload()
        runner = nil
        // Optionally allow the global backend to free when app is truly going idle via notification
    }

    // MARK: - Cancellation
    public func cancel() {
        runner?.cancelCurrent()
    }
    
    // MARK: - Text Generation
    
    public func textStream(from input: LLMInput) async throws -> AsyncThrowingStream<String, Error> {
        guard let runner = runner else {
            throw NoemaLlamaError.invalidParameters
        }
        
        return AsyncThrowingStream<String, Error>(bufferingPolicy: .unbounded) { @Sendable continuation in
            // Bridge llama.cpp callbacks into an async throwing stream. Tie stream lifetime
            // to underlying generation by cancelling the runner when the stream terminates.
            Task { [weak self, input] in
                do {
                    guard let self = self, let runner = self.runner else {
                        continuation.finish(throwing: NoemaLlamaError.invalidParameters)
                        return
                    }
                    
                    let prompt = input.prompt
                    guard !prompt.isEmpty else {
                        continuation.finish(throwing: NoemaLlamaError.invalidParameters)
                        return
                    }

                    let imagePaths: [String]? = {
                        switch input.content {
                        case .multimodal(_, let paths):
                            return paths
                        default:
                            return nil
                        }
                    }()

                    // Log the prompt and any image attachments being sent to the model
                    let promptPreviewLimit = 1000
                    let promptPreview = prompt.count > promptPreviewLimit ? String(prompt.prefix(promptPreviewLimit)) + "… [truncated]" : prompt
                    Task { await logger.log("[Llama][Start] model=\(self.modelURL.lastPathComponent) ctx=\(self.contextLength) temp=\(self.temperature) topP=\(self.topP) topK=\(self.topK)") }
                    Task { await logger.log("[Llama][Prompt] \(promptPreview)") }
                    if let paths = imagePaths, !paths.isEmpty {
                        let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
                        Task { await logger.log("[Llama][Images] count=\(paths.count) names=\(names.joined(separator: ", "))") }
                    }

                    // If images present but this runner build lacks vision support, emit a friendly error
                    if let paths = imagePaths, !paths.isEmpty, !self.visionImagesSupported {
                        continuation.finish(throwing: NSError(domain: "Llama", code: 1001, userInfo: [NSLocalizedDescriptionKey: "This llama.cpp runner was built without vision support."]))
                        return
                    }
                    
                    // Run token generation on a background queue; stream tokens via callback
                    var aggregated = ""
                    if let paths = imagePaths, !paths.isEmpty {
                        runner.generate(withPrompt: prompt, imagePaths: paths, maxTokens: 0, onToken: { token in
                            continuation.yield(token)
                            aggregated += token
                        }, onDone: {
                            let outPreviewLimit = 20000
                            let outPreview = aggregated.count > outPreviewLimit ? String(aggregated.prefix(outPreviewLimit)) + "… [truncated]" : aggregated
                            Task { await logger.log("[Llama][Result] \(outPreview)") }
                            continuation.finish()
                        }, onError: { error in
                            Task { await logger.log("[Llama][Error] \(error.localizedDescription)") }
                            continuation.finish(throwing: error)
                        })
                    } else {
                        runner.generate(withPrompt: prompt, maxTokens: 0, onToken: { token in
                            continuation.yield(token)
                            aggregated += token
                        }, onDone: {
                            let outPreviewLimit = 20000
                            let outPreview = aggregated.count > outPreviewLimit ? String(aggregated.prefix(outPreviewLimit)) + "… [truncated]" : aggregated
                            Task { await logger.log("[Llama][Result] \(outPreview)") }
                            continuation.finish()
                        }, onError: { error in
                            Task { await logger.log("[Llama][Error] \(error.localizedDescription)") }
                            continuation.finish(throwing: error)
                        })
                    }
                } catch {
                    Task { await logger.log("[Llama][Error] \(error.localizedDescription)") }
                    continuation.finish(throwing: error)
                }
            }
            // If the consumer cancels the task iterating this stream, terminate generation.
            continuation.onTermination = { [weak self] _ in
                Task { await logger.log("[Llama][Cancel] Stream terminated by consumer") }
                self?.runner?.cancelCurrent()
            }
        }
    }
    
    public func text(from input: LLMInput) async throws -> String {
        var result = ""
        for try await token in try await textStream(from: input) {
            result += token
        }
        return result
    }
}

// MARK: - Static Factory Method (LocalLLMClient compatibility)

extension NoemaLlamaClient {
    public static func llama(url: URL) async throws -> NoemaLlamaClient {
        let client = NoemaLlamaClient(url: url)
        try await client.load()
        return client
    }
    
    public static func llama(
        url: URL,
        parameter: LlamaParameter
    ) async throws -> NoemaLlamaClient {
        let client = NoemaLlamaClient(
            url: url,
            contextLength: Int32(parameter.contextLength ?? 2048)
        )
        try await client.load()
        return client
    }
}

// MARK: - Parameter Types (LocalLLMClient compatibility)

public struct LlamaParameter {
    public let contextLength: Int?
    public let options: LlamaOptions?
    
    public init(options: LlamaOptions? = nil, contextLength: Int? = nil) {
        self.options = options
        self.contextLength = contextLength
    }
}

public struct LlamaOptions {
    public let extraEOSTokens: [String]
    public let verbose: Bool
    
    public init(extraEOSTokens: [String] = [], verbose: Bool = false) {
        self.extraEOSTokens = extraEOSTokens
        self.verbose = verbose
        if verbose { setenv("NOEMA_LLAMA_VERBOSE", "1", 1) }
    }
}

// MARK: - AnyLLMClient Wrapper

public struct AnyLLMClient: Sendable {
    private let textStreamClosure: @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error>
    private let textClosure: @Sendable (LLMInput) async throws -> String
    private let cancelClosure: (@Sendable () -> Void)?
    private let unloadClosure: (@Sendable () -> Void)?
    private let resetClosure: (@Sendable () async -> Void)?
    
    public init(_ client: NoemaLlamaClient) {
        let streamClosure: @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error> = { input in
            try await client.textStream(from: input)
        }
        self.textStreamClosure = streamClosure
        self.textClosure = { input in
            var result = ""
            for try await token in try await streamClosure(input) {
                result += token
            }
            return result
        }
        self.cancelClosure = { [weak client] in client?.cancel() }
        self.unloadClosure = { [weak client] in client?.unload() }
        self.resetClosure = nil
    }
    
    // Removed LocalLLMClient bridging initializer to avoid undefined symbols
    
#if canImport(LeapSDK)
    public init(_ client: LeapLLMClient) {
        let streamClosure: @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error> = { input in
            try await client.textStream(from: input)
        }
        self.textStreamClosure = streamClosure
        self.textClosure = { input in
            var result = ""
            for try await token in try await streamClosure(input) {
                result += token
            }
            return result
        }
        self.cancelClosure = { Task { await client.cancelActive() } }
        self.unloadClosure = nil
        self.resetClosure = { await client.hardResetConversation() }
    }
#endif
    
    @available(macOS 13.0, iOS 16.0, *)
    public init(_ client: MLXTextClient) {
        let streamClosure: @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error> = { input in
            try await client.textStream(from: input)
        }
        self.textStreamClosure = streamClosure
        self.textClosure = { input in
            var result = ""
            for try await token in try await streamClosure(input) {
                result += token
            }
            return result
        }
        self.cancelClosure = { client.cancel() }
        self.unloadClosure = nil
        self.resetClosure = nil
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    public init(_ client: MLXVLMClient) {
        let streamClosure: @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error> = { input in
            try await client.textStream(from: input)
        }
        self.textStreamClosure = streamClosure
        self.textClosure = { input in
            var result = ""
            for try await token in try await streamClosure(input) {
                result += token
            }
            return result
        }
        self.cancelClosure = { client.cancel() }
        self.unloadClosure = nil
        self.resetClosure = nil
    }
    
    // Convenience initializer to build a failing client for unimplemented adapters.
    public static func makeFailing(message: String) -> AnyLLMClient {
        let stream: @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error> = { _ in
            AsyncThrowingStream<String, Error> { continuation in
                continuation.finish(throwing: NSError(domain: "Noema", code: -999, userInfo: [NSLocalizedDescriptionKey: message]))
            }
        }
        return AnyLLMClient(unsafeStream: stream)
    }

    // Unsafe convenience init to build AnyLLMClient from a custom stream.
    init(unsafeStream: @escaping @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error>) {
        self.textStreamClosure = unsafeStream
        self.textClosure = { input in
            var result = ""
            for try await token in try await unsafeStream(input) {
                result += token
            }
            return result
        }
        self.cancelClosure = nil
        self.unloadClosure = nil
        self.resetClosure = nil
    }

    public init(
        textStream: @escaping @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error>,
        text: (@Sendable (LLMInput) async throws -> String)? = nil,
        cancel: (@Sendable () -> Void)? = nil,
        unload: (@Sendable () -> Void)? = nil,
        reset: (@Sendable () async -> Void)? = nil
    ) {
        self.textStreamClosure = textStream
        if let text {
            self.textClosure = text
        } else {
            self.textClosure = { input in
                var result = ""
                for try await token in try await textStream(input) {
                    result += token
                }
                return result
            }
        }
        self.cancelClosure = cancel
        self.unloadClosure = unload
        self.resetClosure = reset
    }
    
    public func textStream(from input: LLMInput) async throws -> AsyncThrowingStream<String, Error> {
        try await textStreamClosure(input)
    }
    
    public func text(from input: LLMInput) async throws -> String {
        try await textClosure(input)
    }

    public func cancelActive() {
        cancelClosure?()
    }

    public func unload() {
        unloadClosure?()
    }

    public func reset() async {
        await resetClosure?()
    }

    // No explicit reset hooks; conversation continuity is preserved by Leap SDK
}
