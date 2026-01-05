// NoemaLlamaClient.swift
// NoemaLlamaClient.swift - Swift wrapper for our llama.cpp implementation

import Foundation
import Dispatch
import NoemaPackages
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

private actor GenerationCoordinator {
    private var isGenerationActive = false
    private var isUnloading = false
    private var generationWaiters: [CheckedContinuation<Void, Never>] = []
    private var unloadWaiters: [CheckedContinuation<Void, Never>] = []

    func acquireGeneration() async {
        if isUnloading || isGenerationActive {
            await withCheckedContinuation { continuation in
                generationWaiters.append(continuation)
            }
        }
        isGenerationActive = true
    }

    func releaseGeneration() {
        guard isGenerationActive else { return }
        isGenerationActive = false
        if let continuation = unloadWaiters.first {
            unloadWaiters.removeFirst()
            continuation.resume()
        } else if let continuation = generationWaiters.first {
            generationWaiters.removeFirst()
            isGenerationActive = true
            continuation.resume()
        }
    }

    func beginUnload() async {
        if isUnloading {
            await withCheckedContinuation { continuation in
                unloadWaiters.append(continuation)
            }
            return
        }
        isUnloading = true
        if isGenerationActive {
            await withCheckedContinuation { continuation in
                unloadWaiters.append(continuation)
            }
        }
    }

    // Returns true if this caller acquired the unload lock and is responsible for
    // performing the unload. Returns false if it only waited for another unload
    // already in progress to finish.
    func beginUnloadAcquiring() async -> Bool {
        if isUnloading {
            await withCheckedContinuation { continuation in
                unloadWaiters.append(continuation)
            }
            return false
        }
        isUnloading = true
        if isGenerationActive {
            await withCheckedContinuation { continuation in
                unloadWaiters.append(continuation)
            }
        }
        return true
    }

    func endUnload() {
        if let continuation = unloadWaiters.first {
            unloadWaiters.removeFirst()
            continuation.resume()
        } else {
            isUnloading = false
            if let continuation = generationWaiters.first {
                generationWaiters.removeFirst()
                isGenerationActive = true
                continuation.resume()
            }
        }
    }
}

private actor GenerationReleaseToken {
    private var coordinator: GenerationCoordinator?

    init(coordinator: GenerationCoordinator) {
        self.coordinator = coordinator
    }

    func release() async {
        guard let coordinator else { return }
        self.coordinator = nil
        await coordinator.releaseGeneration()
    }
}

private actor StreamState {
    private var didStartGeneration = false

    func markStarted() {
        didStartGeneration = true
    }

    func hasStarted() -> Bool {
        didStartGeneration
    }
}

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
    private var routeAllViaLoopback: Bool = false
    private let modelURL: URL
    private let temperature: Float
    private let topP: Float
    private let topK: Int32
    private let contextLength: Int32
    private let visionMode: LlamaVisionMode
    private let mmprojPath: String?
    private let explicitThreadCount: Int32?
    // Capability flag for vision-enabled builds; set dynamically on load
    private var visionImagesSupported: Bool = false
    // Snapshot of effective load-time knobs for richer logging
    private var effectiveContext: Int32 = 0
    private var effectiveThreads: Int32 = 0
    private var effectiveGpuLayers: Int32 = 0
    private var effectiveMMProj: String? = nil
    private var hasVisionOpsFlag: Bool = false
    private var lastVisionProbe: LlamaVisionProbe = .unavailable
    private let generationCoordinator = GenerationCoordinator()
    
    public init(
        url: URL,
        contextLength: Int32 = 2048,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int32 = 40,
        visionMode: LlamaVisionMode = .auto,
        mmprojPath: String? = nil,
        threadCount: Int32? = nil
    ) {
        self.modelURL = url
        self.contextLength = contextLength
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.visionMode = visionMode
        self.mmprojPath = mmprojPath
        if let threadCount, threadCount > 0 {
            self.explicitThreadCount = threadCount
        } else {
            self.explicitThreadCount = nil
        }
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

            let fallbackThreadCount = Int32(max(1, ProcessInfo.processInfo.processorCount - 2))
            let resolvedThreads: Int32 = {
                if let explicitThreadCount, explicitThreadCount > 0 {
                    return explicitThreadCount
                }
                if let env = threadsEnv, env > 0 {
                    return env
                }
                return fallbackThreadCount
            }()
            let threads = max(Int32(1), resolvedThreads)

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
            if envVerbose {
                fputs("[NoemaLlamaClient] Using \(threads) CPU thread\(threads == 1 ? "" : "s").\n", stderr)
            }
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

            // Decide whether to route everything to the loopback server to avoid
            // double-loading the model (in-process + server).
            let defaults = UserDefaults.standard
            let compiledVision = LlamaRunner.runtimeHasVisionSymbols()
            
            // Check if server is enabled in settings
            let serverEnabledInSettings = defaults.bool(forKey: "serverVisionEnabled")
            
            // If enabled, wait briefly for the port to be reported (handling potential race conditions)
            if serverEnabledInSettings && Int(LlamaServerBridge.port()) <= 0 {
                for _ in 0..<10 { // allow up to ~1s on slower iOS startups
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    if Int(LlamaServerBridge.port()) > 0 { break }
                }
            }
            
            // Prefer server when ChatVM has enabled it or when a server is already bound.
            // Avoid starting/stopping the server here to prevent race conditions with ChatVM.
            let serverActive = Int(LlamaServerBridge.port()) > 0
            let shouldRouteViaServer = serverEnabledInSettings || serverActive

            if shouldRouteViaServer {
                self.routeAllViaLoopback = true
                self.effectiveMMProj = projectorPathToUse
                self.hasVisionOpsFlag = compiledVision
                if envVerbose {
                    let projName = projectorPathToUse.map { URL(fileURLWithPath: $0).lastPathComponent } ?? (GGUFMetadata.hasMultimodalProjector(at: self.modelURL) ? "merged" : "none")
                    fputs("[NoemaLlamaClient] Loopback routing enabled port=\(Int(LlamaServerBridge.port())) gguf=\(self.modelURL.lastPathComponent) mmproj=\(projName)\n", stderr)
                }
            } else {
                if let projectorPathToUse {
                    self.runner = LlamaRunner(
                        modelPath: self.modelURL.path,
                        mmprojPath: projectorPathToUse,
                        nCtxTokens: nCtx,
                        nGpuLayers: nGpuLayers,
                        nThreads: threads
                    )
                    self.effectiveMMProj = projectorPathToUse
                } else {
                    self.runner = LlamaRunner(
                        modelPath: self.modelURL.path,
                        nCtxTokens: nCtx,
                        nGpuLayers: nGpuLayers,
                        nThreads: threads
                    )
                    self.effectiveMMProj = nil
                }
                if self.runner == nil { throw NoemaLlamaError.modelLoadFailed }
                // Detect compile-time vision capability
                self.hasVisionOpsFlag = compiledVision
            }
            self.visionImagesSupported = self.hasVisionOpsFlag
            if self.routeAllViaLoopback {
                // When routing through the loopback server, honor vision unconditionally
                // (the app only enables the server for vision-capable models).
                self.visionImagesSupported = true
            } else if self.hasVisionOpsFlag {
                // Runtime probe to distinguish between compiled-with-vision vs model missing projector
                let probe = self.runner?.probeVision() ?? .unavailable
                self.lastVisionProbe = probe
                // Determine if we effectively have a projector (external or merged)
                let hasMerged = GGUFMetadata.hasMultimodalProjector(at: self.modelURL)
                let hasExternal = (self.effectiveMMProj != nil)
                let hasAnyProjector = hasMerged || hasExternal
                switch self.visionMode {
                case .mergedOnly:
                    // Accept merged projector even if our probe path is unavailable on this build
                    self.visionImagesSupported = (probe == .OK) || (probe == .unavailable && hasMerged)
                case .projectorRequired:
                    // Require a projector but allow runtime symbol-only builds
                    self.visionImagesSupported = (probe == .OK) || (probe == .unavailable && hasAnyProjector)
                case .auto:
                    // Prefer probe OK; otherwise, if symbols are present and a projector exists, allow images
                    self.visionImagesSupported = (probe == .OK) || (probe == .unavailable && hasAnyProjector)
                }
                if envVerbose {
                    if self.visionImagesSupported {
                        fputs("[NoemaLlamaClient] Vision enabled with mode=\(self.visionMode).\n", stderr)
                    } else {
                        fputs("[NoemaLlamaClient] Vision disabled with mode=\(self.visionMode).\n", stderr)
                    }
                }
            }
            // Persist compile/probe status so the UI can gate image controls without having
            // to reach through the client’s internals.
            let userDefaults = UserDefaults.standard
            userDefaults.set(self.hasVisionOpsFlag, forKey: "llama.compiledVision")
            let probeStr: String = {
                switch self.lastVisionProbe {
                case .OK: return "OK"
                case .noProjector: return "noProjector"
                case .unavailable: return "unavailable"
                @unknown default: return "unknown"
                }
            }()
            userDefaults.set(probeStr, forKey: "llama.visionProbe")
            userDefaults.set(self.effectiveMMProj ?? "", forKey: "llama.mmprojPath")
            userDefaults.synchronize()
            // Remember the effective knobs used when creating the runner
            self.effectiveContext = nCtx
            self.effectiveThreads = threads
            self.effectiveGpuLayers = nGpuLayers
            if envVerbose {
                let mm = self.effectiveMMProj != nil ? URL(fileURLWithPath: self.effectiveMMProj!).lastPathComponent : (GGUFMetadata.hasMultimodalProjector(at: self.modelURL) ? "merged" : "none")
                let caps = "compiledVision=\(self.hasVisionOpsFlag) probe=\(self.lastVisionProbe)"
                fputs("[NoemaLlamaClient] Load flags: ctx=\(nCtx) n_gpu_layers=\(nGpuLayers) threads=\(threads) mmproj=\(mm) \(caps)\n", stderr)
            }
        }.value
    }
    
    public func unload() {
        Task.detached { [weak self] in
            guard let strongSelf = self else {
                return
            }
            fputs("[NoemaLlamaClient] Unload requested. Waiting for active generation to finish...\n", stderr)
            await strongSelf.generationCoordinator.beginUnload()
            strongSelf.runner?.cancelCurrent()
            strongSelf.runner?.unload()
            strongSelf.runner = nil
            if strongSelf.routeAllViaLoopback {
                LlamaServerBridge.stop()
                UserDefaults.standard.set(false, forKey: "serverVisionEnabled")
            }
            await strongSelf.generationCoordinator.endUnload()
            fputs("[NoemaLlamaClient] Unloaded and resources released.\n", stderr)
        }
        // Optionally allow the global backend to free when app is truly going idle via notification
    }

    // Explicit unload that only returns once resources are released.
    // Performs work off the main actor and coordinates with any in-flight unload.
    public func unloadAndWait() async {
        // Execute heavy teardown work on a utility-priority task.
        await Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let acquired = await self.generationCoordinator.beginUnloadAcquiring()
            if acquired {
                self.runner?.cancelCurrent()
                self.runner?.unload()
                self.runner = nil
                if self.routeAllViaLoopback {
                    LlamaServerBridge.stop()
                    UserDefaults.standard.set(false, forKey: "serverVisionEnabled")
                }
                await self.generationCoordinator.endUnload()
                fputs("[NoemaLlamaClient] Unloaded and resources released (awaited).\n", stderr)
            } else {
                // Another unload finished while we were waiting. Nothing left to do.
            }
        }.value
    }

    // MARK: - Cancellation
    public func cancel() {
        runner?.cancelCurrent()
    }
    
    // MARK: - Text Generation
    
    public func textStream(from input: LLMInput) async throws -> AsyncThrowingStream<String, Error> {
        // If configured to use the loopback server for all requests, bypass the runner.
        if routeAllViaLoopback {
            await generationCoordinator.acquireGeneration()
            if Task.isCancelled { await generationCoordinator.releaseGeneration(); throw CancellationError() }
            let releaseToken = GenerationReleaseToken(coordinator: generationCoordinator)
            let streamState = StreamState()
            return AsyncThrowingStream<String, Error>(bufferingPolicy: .unbounded) { @Sendable continuation in
                Task { [weak self, input, releaseToken, streamState] in
                    do {
                        guard let self = self else {
                            await releaseToken.release();
                            continuation.finish(throwing: NoemaLlamaError.invalidParameters)
                            return
                        }
                        let prompt = input.prompt
                        guard !prompt.isEmpty else {
                            await releaseToken.release();
                            continuation.finish(throwing: NoemaLlamaError.invalidParameters)
                            return
                        }
                        let imagePaths: [String] = {
                            switch input.content { case .multimodal(_, let paths): return paths; default: return [] }
                        }()
                        let responseText = try await self.generateViaLoopbackServer(prompt: prompt, imagePaths: imagePaths)
                        await streamState.markStarted()
                        for word in responseText.split(separator: " ") { continuation.yield(String(word) + " ") }
                        continuation.finish()
                        Task { await releaseToken.release() }
                    } catch {
                        Task { await logger.log("[Llama][ServerError] \(error.localizedDescription)") }
                        await releaseToken.release()
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { [releaseToken, streamState] _ in
                    Task { if await !streamState.hasStarted() { await releaseToken.release() } }
                }
            }
        }

        guard runner != nil else { throw NoemaLlamaError.invalidParameters }
        await generationCoordinator.acquireGeneration()
        if Task.isCancelled { await generationCoordinator.releaseGeneration(); throw CancellationError() }
        let releaseToken = GenerationReleaseToken(coordinator: generationCoordinator)
        let streamState = StreamState()

        return AsyncThrowingStream<String, Error>(bufferingPolicy: .unbounded) { @Sendable continuation in
            // Bridge llama.cpp callbacks into an async throwing stream. Tie stream lifetime
            // to underlying generation by cancelling the runner when the stream terminates.
            Task { [weak self, input, releaseToken, streamState] in
                do {
                    guard let self = self, let runner = self.runner else {
                        await releaseToken.release()
                        continuation.finish(throwing: NoemaLlamaError.invalidParameters)
                        return
                    }

                    let prompt = input.prompt
                    guard !prompt.isEmpty else {
                        await releaseToken.release()
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
                    let modelName = self.modelURL.lastPathComponent
                    // Build a comprehensive flag summary from env + load snapshot
                    let summary = Self.makeGenerationFlagSummary(
                        modelName: modelName,
                        ctx: self.effectiveContext > 0 ? self.effectiveContext : self.contextLength,
                        threads: self.effectiveThreads,
                        gpuLayers: self.effectiveGpuLayers,
                        mmproj: self.effectiveMMProj,
                        hasVisionOps: self.hasVisionOpsFlag,
                        probe: self.lastVisionProbe
                    )
                    Task { await logger.log("[Llama][Start] \(summary)") }
                    Task { await logger.log("[Llama][Prompt] \(promptPreview)") }
                    if let paths = imagePaths, !paths.isEmpty {
                        let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
                        Task { await logger.log("[Llama][Images] count=\(paths.count) names=\(names.joined(separator: ", "))") }
                        // Log runtime probe details so mismatches are visible next to attachments
                        let mm = self.effectiveMMProj != nil ? URL(fileURLWithPath: self.effectiveMMProj!).lastPathComponent : (GGUFMetadata.hasMultimodalProjector(at: self.modelURL) ? "merged" : "none")
                        let probeDesc: String = {
                            switch self.lastVisionProbe {
                            case .OK: return "OK"
                            case .noProjector: return "noProjector"
                            case .unavailable: return "unavailable"
                            @unknown default: return "unknown"
                            }
                        }()
                        Task { await logger.log("[Images][Probe] compiled=\(self.hasVisionOpsFlag) mmproj=\(mm) result=\(probeDesc)") }
                    }

                    let serverVisionEnabled = UserDefaults.standard.bool(forKey: "serverVisionEnabled")
                    let loopbackAvailable = self.routeAllViaLoopback || serverVisionEnabled || Int(LlamaServerBridge.port()) > 0

                    // If images are present, prefer loopback because the embedded xcframework slices lack vision ops on iOS.
                    if let paths = imagePaths, !paths.isEmpty, loopbackAvailable {
                        do {
                            let imgCount = paths.count
                            let reason = self.routeAllViaLoopback ? "all" : "vision-loopback"
                            Task { await logger.log("[Loopback] route reason=\(reason) images=\(imgCount) port=\(Int(LlamaServerBridge.port()))") }
                            let responseText = try await self.generateViaLoopbackServer(prompt: prompt, imagePaths: paths)
                            // Simulate streaming by chunking on whitespace
                            let words = responseText.split(separator: " ")
                            for word in words { continuation.yield(String(word) + " ") }
                            continuation.finish()
                            Task { await releaseToken.release() }
                            return
                        } catch {
                            Task { await logger.log("[Llama][ServerFallbackError] \(error.localizedDescription)") }
                            await releaseToken.release()
                            continuation.finish(throwing: error)
                            return
                        }
                    }

                    if let paths = imagePaths, !paths.isEmpty, !self.visionImagesSupported {
                        let reason: String = {
                            #if canImport(Foundation)
                            if let r = self.runner?.probeVision() {
                                switch r {
                                case .noProjector:
                                    return "Loaded model is missing a matching projector (.gguf). Place the projector next to the model or use merged VLM weights."
                                case .unavailable:
                                    return "This llama.cpp build lacks vision support (llava/clip not available). Use a vision-enabled build."
                                default:
                                    return "Vision is unavailable for this model/build. Ensure a vision-capable GGUF and matching projector are present."
                                }
                            }
                            #endif
                            return "Vision is unavailable for this model/build. Ensure a vision-capable GGUF and matching projector are present."
                        }()
                        await releaseToken.release()
                        continuation.finish(throwing: NSError(domain: "Llama", code: 1001, userInfo: [NSLocalizedDescriptionKey: reason]))
                        return
                    }
                    
                    // Route all requests via loopback when configured.
                    if loopbackAvailable {
                        do {
                            let imgCount = imagePaths?.count ?? 0
                            let reason = self.routeAllViaLoopback ? "all" : "vision-loopback"
                            Task { await logger.log("[Loopback] route reason=\(reason) images=\(imgCount) port=\(Int(LlamaServerBridge.port()))") }
                            let responseText = try await self.generateViaLoopbackServer(prompt: prompt, imagePaths: imagePaths ?? [])
                            // Simulate streaming by chunking on whitespace
                            let words = responseText.split(separator: " ")
                            for word in words { continuation.yield(String(word) + " ") }
                            continuation.finish()
                            Task { await releaseToken.release() }
                            return
                        } catch {
                            Task { await logger.log("[Llama][ServerFallbackError] \(error.localizedDescription)") }
                            await releaseToken.release()
                            continuation.finish(throwing: error)
                            return
                        }
                    }

                    // Run token generation on a background queue; stream tokens via callback
                    await streamState.markStarted()
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
                            Task { await releaseToken.release() }
                        }, onError: { error in
                            Task { await logger.log("[Llama][Error] \(error.localizedDescription)") }
                            Task { await releaseToken.release() }
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
                            Task { await releaseToken.release() }
                        }, onError: { error in
                            Task { await logger.log("[Llama][Error] \(error.localizedDescription)") }
                            Task { await releaseToken.release() }
                            continuation.finish(throwing: error)
                        })
                    }
                } catch {
                    Task { await logger.log("[Llama][Error] \(error.localizedDescription)") }
                    await releaseToken.release()
                    continuation.finish(throwing: error)
                }
            }
            // If the consumer cancels the task iterating this stream, terminate generation.
            continuation.onTermination = { [weak self, releaseToken, streamState] termination in
                Task {
                    if case .cancelled = termination {
                        await logger.log("[Llama][Cancel] Stream terminated by consumer")
                        self?.runner?.cancelCurrent()
                        if await !streamState.hasStarted() {
                            await releaseToken.release()
                        }
                    } else if await !streamState.hasStarted() {
                        await releaseToken.release()
                    }
                }
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
        let context = parameter.contextLength ?? 2048
        let context32 = Int32(clamping: max(1, context))
        let threadOverride = parameter.threadCount.flatMap { value -> Int32? in
            guard value > 0 else { return nil }
            return Int32(clamping: value)
        }
        let client = NoemaLlamaClient(
            url: url,
            contextLength: context32,
            mmprojPath: parameter.mmproj,
            threadCount: threadOverride
        )
        try await client.load()
        return client
    }
}

// MARK: - Parameter Types (LocalLLMClient compatibility)

public struct LlamaParameter {
    public let contextLength: Int?
    public let options: LlamaOptions?
    public let threadCount: Int?
    public let mmproj: String?
    
    public init(options: LlamaOptions? = nil, contextLength: Int? = nil, threadCount: Int? = nil, mmproj: String? = nil) {
        self.options = options
        self.contextLength = contextLength
        self.threadCount = threadCount
        self.mmproj = mmproj
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

// MARK: - Flag summary helpers

extension NoemaLlamaClient {
    /// Builds a concise, single-line summary of generation flags used by llama.cpp.
    /// Pulls values from environment variables (set via ChatVM/RelayServerEngine) and load-time snapshot.
    static func makeGenerationFlagSummary(
        modelName: String,
        ctx: Int32,
        threads: Int32,
        gpuLayers: Int32,
        mmproj: String?,
        hasVisionOps: Bool,
        probe: LlamaVisionProbe
    ) -> String {
        func env(_ k: String) -> String? { guard let v = getenv(k) else { return nil }; return String(cString: v) }
        func yn(_ s: String?) -> String { (s == "1" || s?.lowercased() == "true") ? "on" : "off" }
        let temp = env("NOEMA_TEMPERATURE") ?? "0.7"
        let topK = env("NOEMA_TOP_K") ?? "40"
        let topP = env("NOEMA_TOP_P") ?? "0.9"
        let minP = env("NOEMA_MIN_P")
        let rep = env("NOEMA_REPEAT_PENALTY")
        let lastN = env("NOEMA_REPEAT_LAST_N")
        let pres = env("NOEMA_PRESENCE_PENALTY")
        let freq = env("NOEMA_FREQUENCY_PENALTY")
        let seed = env("LLAMA_SEED")
        let mmap = yn(env("LLAMA_MMAP"))
        let keep = yn(env("LLAMA_KEEP"))
        let kvOff = yn(env("LLAMA_KV_OFFLOAD"))
        let flash = env("LLAMA_FLASH_ATTENTION")
        let kq = env("LLAMA_K_QUANT")
        let vq = env("LLAMA_V_QUANT")
        let rope = env("NOEMA_ROPE_SCALING")
        let ropeBase = env("NOEMA_ROPE_BASE")
        let ropeFactor = env("NOEMA_ROPE_FACTOR")
        let draftID = env("NOEMA_DRAFT_MODEL")
        let draftMode = env("NOEMA_DRAFT_MODE")
        let draftValue = env("NOEMA_DRAFT_VALUE")
        let promptCache = env("NOEMA_PROMPT_CACHE")
        let promptCacheAll = yn(env("NOEMA_PROMPT_CACHE_ALL"))

        var parts: [String] = []
        parts.append("model=\(modelName)")
        parts.append("ctx=\(ctx)")
        if threads > 0 { parts.append("threads=\(threads)") }
        parts.append("n_gpu_layers=\(gpuLayers)")
        // mmproj: use file name only for brevity
        let mm: String
        if let m = mmproj, !m.isEmpty { mm = URL(fileURLWithPath: m).lastPathComponent } else { mm = "merged/none" }
        parts.append("mmproj=\(mm)")

        // Sampler
        parts.append("temp=\(temp)")
        parts.append("topP=\(topP)")
        parts.append("topK=\(topK)")
        if let minP { parts.append("minP=\(minP)") }
        if let rep { parts.append("repeat_penalty=\(rep)") }
        if let lastN { parts.append("repeat_last_n=\(lastN)") }
        if let pres { parts.append("presence_penalty=\(pres)") }
        if let freq { parts.append("frequency_penalty=\(freq)") }

        // KV / runtime
        if let kq { parts.append("K=\(kq)") }
        if let vq { parts.append("V=\(vq)") }
        if let flash { parts.append("flash=\(flash)") }
        parts.append("mmap=\(mmap)")
        parts.append("keep=\(keep)")
        parts.append("kv_offload=\(kvOff)")
        if let seed { parts.append("seed=\(seed)") }

        // Rope scaling (optional)
        if rope == "yarn" { parts.append("rope=yarn base=\(ropeBase ?? "?") factor=\(ropeFactor ?? "?")") }

        // Prompt cache
        if let promptCache, !promptCache.isEmpty {
            parts.append("pcache=on(")
            parts.append(URL(fileURLWithPath: promptCache).lastPathComponent + ")")
            parts.append("pcache_all=\(promptCacheAll)")
        } else { parts.append("pcache=off") }

        // Speculative decoding
        if let draftID, !draftID.isEmpty {
            parts.append("draft=\(draftID) mode=\(draftMode ?? "tokens") value=\(draftValue ?? "?")")
        }

        // Vision
        let probeStr: String = {
            switch probe {
            case .OK: return "OK"
            case .noProjector: return "noProjector"
            case .unavailable: return "unavailable"
            @unknown default: return "unknown"
            }
        }()
        parts.append("vision.compiled=\(hasVisionOps)")
        parts.append("vision.probe=\(probeStr)")

        return parts.joined(separator: " ")
    }
}

// MARK: - AnyLLMClient Wrapper

public struct AnyLLMClient: Sendable {
    private let textStreamClosure: @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error>
    private let textClosure: @Sendable (LLMInput) async throws -> String
    private let cancelClosure: (@Sendable () -> Void)?
    private let unloadClosure: (@Sendable () -> Void)?
    private let unloadAsyncClosure: (@Sendable () async -> Void)?
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
        self.unloadAsyncClosure = { [weak client] in await client?.unloadAndWait() }
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
        self.unloadAsyncClosure = nil
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
        self.unloadAsyncClosure = nil
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
        self.unloadAsyncClosure = nil
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
        self.unloadAsyncClosure = nil
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
        self.unloadAsyncClosure = nil
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

    public func unloadAndWait() async {
        if let unloadAsyncClosure {
            await unloadAsyncClosure()
        } else {
            unloadClosure?()
        }
    }

    public func reset() async {
        await resetClosure?()
    }

    // No explicit reset hooks; conversation continuity is preserved by Leap SDK
}

// MARK: - Loopback server multimodal fallback (member of NoemaLlamaClient)
extension NoemaLlamaClient {
    private func reencodeIfNeeded(path: String) -> (data: Data, mime: String) {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        // Prefer PNG/JPEG for server compatibility; HEIC/HEIF are not widely supported by stb_image.
        #if canImport(UIKit)
        if let img = UIImage(contentsOfFile: path) {
            // Re-encode to JPEG (quality 0.9) for broad compatibility
            if let jpeg = img.jpegData(compressionQuality: 0.9) {
                Task { await logger.log("[Images][Reencode] iOS src=\(ext) -> jpeg bytes=\(jpeg.count) name=\(URL(fileURLWithPath: path).lastPathComponent)") }
                return (jpeg, "image/jpeg")
            }
            if let png = img.pngData() {
                Task { await logger.log("[Images][Reencode] iOS src=\(ext) -> png bytes=\(png.count) name=\(URL(fileURLWithPath: path).lastPathComponent)") }
                return (png, "image/png")
            }
        }
        #elseif canImport(AppKit)
        if let image = NSImage(contentsOfFile: path) {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                // Fallback to PNG
                if let tiff = image.tiffRepresentation,
                   let rep2 = NSBitmapImageRep(data: tiff),
                   let png = rep2.representation(using: .png, properties: [:]) {
                    Task { await logger.log("[Images][Reencode] macOS src=\(ext) -> png bytes=\(png.count) name=\(URL(fileURLWithPath: path).lastPathComponent)") }
                    return (png, "image/png")
                }
                // Last resort: file bytes
                let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
                Task { await logger.log("[Images][Reencode] macOS fallback bytes=\(data.count) name=\(URL(fileURLWithPath: path).lastPathComponent)") }
                return (data, ext == "png" ? "image/png" : "image/jpeg")
            }
            Task { await logger.log("[Images][Reencode] macOS src=\(ext) -> jpeg bytes=\(jpeg.count) name=\(URL(fileURLWithPath: path).lastPathComponent)") }
            return (jpeg, "image/jpeg")
        }
        #endif
        // Default: use original bytes and guess mime from extension
        let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
        switch ext {
        case "png": return (data, "image/png")
        case "jpg", "jpeg": return (data, "image/jpeg")
        case "webp": return (data, "image/webp")
        default: return (data, "image/jpeg")
        }
    }

    fileprivate func generateViaLoopbackServer(prompt: String, imagePaths: [String]) async throws -> String {
        // Off-grid guard with explicit log so users know why local loopback is blocked.
        if NetworkKillSwitch.isEnabled {
            Task { await logger.log("[Loopback] blocked by off-grid/kill-switch") }
            throw URLError(.notConnectedToInternet)
        }
        // Ensure RAM safety and keep the loopback server aligned with the active model settings.
        let ctxForRAM = Int(self.effectiveContext > 0 ? self.effectiveContext : self.contextLength)
        if let size = (try? FileManager.default.attributesOfItem(atPath: self.modelURL.path)[.size]) as? Int64 {
            if ModelRAMAdvisor.fitsInRAM(format: .gguf, sizeBytes: size, contextLength: ctxForRAM, layerCount: nil, moeInfo: nil) == false {
                Task { await logger.log("[Loopback][RAMGuard] blocked model=\(self.modelURL.lastPathComponent) ctx=\(ctxForRAM)") }
                throw NSError(
                    domain: "Noema",
                    code: 2003,
                    userInfo: [NSLocalizedDescriptionKey: "Loopback server blocked by RAM safety guard for this model/context. Lower context length or bypass the safety check."]
                )
            }
        }
        // Re-assert context length for the embedded server so it matches the current model settings.
        setenv("LLAMA_CONTEXT_SIZE", String(ctxForRAM), 1)
        var port = Int(LlamaServerBridge.port())
        if port <= 0 {
            // Best-effort lazy start: if a projector is available and the embedded build lacks vision,
            // spin up the server now.
            let mm = self.effectiveMMProj ?? ProjectorLocator.projectorPath(alongside: self.modelURL)
            if let mm, !mm.isEmpty {
                let p = Int(LlamaServerBridge.start(host: "127.0.0.1", preferredPort: 0, ggufPath: self.modelURL.path, mmprojPath: mm))
                if p > 0 {
                    UserDefaults.standard.set(true, forKey: "serverVisionEnabled")
                    Task { await logger.log("[Loopback] lazyStart ok port=\(p) gguf=\(self.modelURL.lastPathComponent) mmproj=\(URL(fileURLWithPath: mm).lastPathComponent)") }
                    port = p
                    // Free in-process runner memory if it was previously loaded.
                    if self.runner != nil {
                        self.runner?.cancelCurrent()
                        self.runner?.unload()
                        self.runner = nil
                    }
                    self.routeAllViaLoopback = true
                } else {
                    Task { await logger.log("[Loopback] lazyStart failed gguf=\(self.modelURL.lastPathComponent) mmproj=\(URL(fileURLWithPath: mm).lastPathComponent)") }
                }
            }
        }
        guard port > 0, let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            throw NSError(domain: "Noema", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Loopback server not running"])
        }
        func makeImageObject(from path: String) -> [String: Any] {
            let (data, mime) = reencodeIfNeeded(path: path)
            let b64 = data.base64EncodedString()
            return [
                "type": "image_url",
                "image_url": ["url": "data:\(mime);base64,\(b64)"]
            ]
        }
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        content.append(contentsOf: imagePaths.map(makeImageObject(from:)))
        // Pull current sampling knobs from environment variables, which ChatVM sets from ModelSettings
        func env(_ k: String) -> String? { guard let v = getenv(k) else { return nil }; return String(cString: v) }
        var body: [String: Any] = [
            "model": self.modelURL.lastPathComponent,
            "messages": [["role": "user", "content": content]],
            "stream": false
        ]
        if let s = env("LLAMA_SEED"), let n = Int(s) { body["seed"] = n }
        if let t = env("NOEMA_TEMPERATURE"), let f = Double(t) { body["temperature"] = f }
        if let k = env("NOEMA_TOP_K"), let n = Int(k) { body["top_k"] = n }
        if let p = env("NOEMA_TOP_P"), let f = Double(p) { body["top_p"] = f }
        if let mp = env("NOEMA_MIN_P"), let f = Double(mp) { body["min_p"] = f }
        if let rp = env("NOEMA_REPEAT_PENALTY"), let f = Double(rp) { body["repeat_penalty"] = f }
        if let rl = env("NOEMA_REPEAT_LAST_N"), let n = Int(rl) { body["repeat_last_n"] = n }
        if let pr = env("NOEMA_PRESENCE_PENALTY"), let f = Double(pr) { body["presence_penalty"] = f }
        if let fr = env("NOEMA_FREQUENCY_PENALTY"), let f = Double(fr) { body["frequency_penalty"] = f }
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let approxBytes: Int = content.reduce(0) { acc, item in
            let urlStr = ((item["image_url"] as? [String: Any])?["url"] as? String) ?? ""
            return acc + urlStr.count
        }
        Task { await logger.log("[Loopback] request url=\(baseURL)/v1/chat/completions images=\(imagePaths.count) bytes=\(approxBytes)") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(decoding: data, as: UTF8.self)
            throw NSError(domain: "Noema", code: 2002, userInfo: [NSLocalizedDescriptionKey: "Server error: \(msg)"])
        }
        struct ChatResp: Decodable { struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }; let choices: [Choice] }
        let decoded = try JSONDecoder().decode(ChatResp.self, from: data)
        let out = decoded.choices.first?.message.content ?? ""
        Task { await logger.log("[Loopback] response ok chars=\(out.count)") }
        return out
    }
}
