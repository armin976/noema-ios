import Foundation
import ImageIO
import CoreGraphics
#if os(iOS) && canImport(ExecuTorch) && canImport(ExecuTorchLLM)
import ExecuTorch
import ExecuTorchLLM

@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
final actor ExecuTorchLLMClient {
    private enum State {
        case idle
        case loaded
    }

    private let modelPath: String
    private let tokenizerPath: String
    private let settings: ModelSettings
    private let isVision: Bool

    private var textRunner: TextRunner?
    private var multimodalRunner: MultimodalRunner?
    private var state: State = .idle
    private var activeGenerationTask: Task<Void, Never>? = nil
    private var systemPrompt: String? = nil
    private var resolvedRuntimeBackends: [String] = []
    private var resolvedRuntimeMethod: String? = nil

    init(modelPath: String, tokenizerPath: String, isVision: Bool, settings: ModelSettings) {
        self.modelPath = modelPath
        self.tokenizerPath = tokenizerPath
        self.isVision = isVision
        self.settings = settings
    }

    func load() async throws {
        guard state == .idle else { return }
        do {
            let runtimeInfo = Self.inspectRuntimeBackends(modelPath: modelPath)
            resolvedRuntimeBackends = runtimeInfo.backends
            resolvedRuntimeMethod = runtimeInfo.methodName
            await Self.logRuntimeBackendInfo(
                runtimeInfo,
                stage: "load",
                modelPath: modelPath,
                isVision: isVision
            )

            if isVision {
                let runner = MultimodalRunner(modelPath: modelPath, tokenizerPath: tokenizerPath)
                try runner.load()
                self.multimodalRunner = runner
            } else {
                let runner = TextRunner(modelPath: modelPath, tokenizerPath: tokenizerPath)
                try runner.load()
                self.textRunner = runner
            }
            self.state = .loaded
        } catch {
            throw Self.enrichedLoadError(error)
        }
    }

    func unload() {
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        textRunner?.stop()
        multimodalRunner?.stop()
        textRunner = nil
        multimodalRunner = nil
        state = .idle
    }

    func cancelActive() {
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        textRunner?.stop()
        multimodalRunner?.stop()
    }

    func resetConversation() {
        textRunner?.reset()
        multimodalRunner?.reset()
    }

    func hardResetConversation() {
        resetConversation()
    }

    func setSystemPrompt(_ prompt: String?) {
        systemPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func syncSystemPrompt(_ prompt: String?) {
        setSystemPrompt(prompt)
    }

    func textStream(from input: LLMInput) async throws -> AsyncThrowingStream<String, Error> {
        try await load()

        let payload = try PreparedPayload(
            input: input,
            isVision: isVision,
            systemPrompt: systemPrompt
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runGeneration(payload: payload, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task {
                    await self?.cancelActive()
                }
            }

            Task {
                await self.setActiveTask(task)
            }
        }
    }

    private func setActiveTask(_ task: Task<Void, Never>?) {
        activeGenerationTask = task
    }

    private static func enrichedLoadError(_ error: Error) -> Error {
        let nsError = error as NSError
        let normalizedDomain = nsError.domain.lowercased()
        guard normalizedDomain.contains("executorch") else {
            return error
        }

        let code = nsError.code
        let codeName = execuTorchErrorName(for: code)
        var parts: [String] = [
            "ExecuTorch failed to load this model.",
            "Runtime error: \(nsError.domain) code \(code) (\(codeName))."
        ]
        if let hint = execuTorchErrorHint(for: code) {
            parts.append(hint)
        }

        return NSError(
            domain: "Noema.ExecuTorch",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: parts.joined(separator: " "),
                NSUnderlyingErrorKey: nsError
            ]
        )
    }

    private static func execuTorchErrorName(for code: Int) -> String {
        switch code {
        case 0: return "Ok"
        case 1: return "Internal"
        case 2: return "InvalidState"
        case 3: return "EndOfMethod"
        case 16: return "NotSupported"
        case 17: return "NotImplemented"
        case 18: return "InvalidArgument"
        case 19: return "InvalidType"
        case 20: return "OperatorMissing"
        case 21: return "RegistrationExceedingMaxKernels"
        case 22: return "RegistrationAlreadyRegistered"
        case 32: return "NotFound"
        case 33: return "MemoryAllocationFailed"
        case 34: return "AccessFailed"
        case 35: return "InvalidProgram"
        case 36: return "InvalidExternalData"
        case 37: return "OutOfResources"
        case 48: return "DelegateInvalidCompatibility"
        case 49: return "DelegateMemoryAllocationFailed"
        case 50: return "DelegateInvalidHandle"
        default: return "Unknown"
        }
    }

    private static func execuTorchErrorHint(for code: Int) -> String? {
        switch code {
        case 17:
            return "This usually means the .pte was exported for a different/newer ExecuTorch runtime or uses unsupported kernels. Re-export with a matching runtime/backend, or upgrade this app's ExecuTorch dependency (swiftpm-1.1.0+ recommended)."
        case 20:
            return "The model references operators that are missing from this runtime build."
        case 35, 36:
            return "The model files appear incompatible or corrupted (program/external data mismatch)."
        case 32:
            return "A required model artifact is missing (for example tokenizer or sidecar data)."
        case 48, 49, 50:
            return "The selected backend delegate is incompatible or failed to initialize."
        default:
            return nil
        }
    }

    private func generationConfig() -> Config {
        Config { cfg in
            cfg.isEchoEnabled = false
            cfg.maximumNewTokens = max(1, Int(settings.contextLength.rounded(.up)))
            cfg.sequenceLength = max(128, Int(settings.contextLength.rounded(.up)))
            cfg.temperature = settings.temperature
            cfg.isWarming = true
            cfg.bosCount = 0
            cfg.eosCount = 0
        }
    }

    private func runGeneration(payload: PreparedPayload, continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        let cfg = generationConfig()
        let runtimeSummary = resolvedRuntimeBackends.isEmpty
            ? "unknown"
            : resolvedRuntimeBackends.joined(separator: ",")
        let methodLabel = resolvedRuntimeMethod ?? "<unknown>"
        await logger.log(
            "[ExecuTorch][Run] mode=\(isVision ? "multimodal" : "text") method=\(methodLabel) backends=\(runtimeSummary)"
        )

        switch payload {
        case .text(let prompt):
            guard let textRunner else {
                throw NSError(domain: "Noema.ExecuTorch", code: -1001, userInfo: [NSLocalizedDescriptionKey: "ExecuTorch text runner not loaded."])
            }
            try textRunner.generate(prompt, cfg) { token in
                continuation.yield(token)
            }
        case .multimodal(let inputs):
            guard let multimodalRunner else {
                throw NSError(domain: "Noema.ExecuTorch", code: -1002, userInfo: [NSLocalizedDescriptionKey: "ExecuTorch multimodal runner not loaded."])
            }
            try multimodalRunner.generate(inputs, cfg) { token in
                continuation.yield(token)
            }
        }

        activeGenerationTask = nil
    }

    private struct RuntimeBackendInfo {
        let methodName: String?
        let backends: [String]
        let byMethod: [(String, [String])]
        let inspectionError: String?
    }

    private static func inspectRuntimeBackends(modelPath: String) -> RuntimeBackendInfo {
        do {
            let module = Module(filePath: modelPath)
            _ = try module.load()
            let methods = try module.methodNames().sorted()

            var byMethodMap: [String: [String]] = [:]
            var union: Set<String> = []

            for method in methods {
                let metadata = try module.methodMetadata(method)
                let normalized = normalizeBackendNames(metadata.backendNames)
                if normalized.isEmpty { continue }
                byMethodMap[method] = normalized
                union.formUnion(normalized)
            }

            let preferredMethod = preferredMethodName(from: methods)
            let selectedBackends: [String] = {
                if let preferredMethod, let methodBackends = byMethodMap[preferredMethod] {
                    return methodBackends
                }
                return Array(union).sorted()
            }()

            let byMethod = byMethodMap
                .map { ($0.key, $0.value) }
                .sorted { $0.0 < $1.0 }

            return RuntimeBackendInfo(
                methodName: preferredMethod,
                backends: selectedBackends,
                byMethod: byMethod,
                inspectionError: nil
            )
        } catch {
            return RuntimeBackendInfo(
                methodName: nil,
                backends: [],
                byMethod: [],
                inspectionError: error.localizedDescription
            )
        }
    }

    private static func preferredMethodName(from methods: [String]) -> String? {
        let ordered = methods.sorted()
        if let exactForward = ordered.first(where: { $0.lowercased() == "forward" }) {
            return exactForward
        }
        if let generateLike = ordered.first(where: { $0.lowercased().contains("generate") }) {
            return generateLike
        }
        if let chatLike = ordered.first(where: { $0.lowercased().contains("chat") }) {
            return chatLike
        }
        return ordered.first
    }

    private static func normalizeBackendNames(_ names: [String]) -> [String] {
        let mapped = names
            .map { raw -> String in
                let lower = raw.lowercased()
                if lower.contains("xnn") { return "XNNPACK" }
                if lower.contains("coreml") || lower.contains("core_ml") { return "CoreML" }
                if lower.contains("mps") { return "MPS" }
                if lower.contains("portable") { return "Portable" }
                if lower.contains("cpu") { return "CPU" }
                return raw
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(mapped)).sorted()
    }

    private static func logRuntimeBackendInfo(
        _ info: RuntimeBackendInfo,
        stage: String,
        modelPath: String,
        isVision: Bool
    ) async {
        let modelName = URL(fileURLWithPath: modelPath).lastPathComponent
        let mode = isVision ? "multimodal" : "text"

        if let inspectionError = info.inspectionError {
            await logger.log(
                "[ExecuTorch][Backend] stage=\(stage) model=\(modelName) mode=\(mode) resolve=failed error=\(inspectionError)"
            )
            return
        }

        let resolved = info.backends.isEmpty ? "unknown" : info.backends.joined(separator: ",")
        let methodLabel = info.methodName ?? "<unknown>"
        await logger.log(
            "[ExecuTorch][Backend] stage=\(stage) model=\(modelName) mode=\(mode) method=\(methodLabel) resolved=\(resolved)"
        )

        if !info.byMethod.isEmpty {
            let matrix = info.byMethod
                .map { "\($0.0)=\($0.1.joined(separator: ","))" }
                .joined(separator: " | ")
            await logger.log("[ExecuTorch][Backend] methods=\(matrix)")
        }
    }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
private enum PreparedPayload {
    case text(String)
    case multimodal([MultimodalInput])

    init(input: LLMInput, isVision: Bool, systemPrompt: String?) throws {
        switch input.content {
        case .plain(let text):
            self = .text(Self.applySystemPrompt(text: text, systemPrompt: systemPrompt))
        case .messages(let messages):
            let rendered = messages
                .map { "\($0.role): \($0.content)" }
                .joined(separator: "\n")
            self = .text(Self.applySystemPrompt(text: rendered, systemPrompt: systemPrompt))
        case .multimodal(let text, let imagePaths):
            let prompt = Self.applySystemPrompt(text: text, systemPrompt: systemPrompt)
            guard isVision else {
                self = .text(prompt)
                return
            }
            var items: [MultimodalInput] = [MultimodalInput(prompt)]
            for imagePath in imagePaths {
                let image = try ETImageDecoder.decodeImage(fromPath: imagePath)
                items.append(MultimodalInput(image))
            }
            self = .multimodal(items)
        case .multimodalMessages(let messages, let imagePaths):
            let rendered = messages
                .map { "\($0.role): \($0.content)" }
                .joined(separator: "\n")
            let prompt = Self.applySystemPrompt(text: rendered, systemPrompt: systemPrompt)
            guard isVision else {
                self = .text(prompt)
                return
            }
            var items: [MultimodalInput] = [MultimodalInput(prompt)]
            for imagePath in imagePaths {
                let image = try ETImageDecoder.decodeImage(fromPath: imagePath)
                items.append(MultimodalInput(image))
            }
            self = .multimodal(items)
        }
    }

    private static func applySystemPrompt(text: String, systemPrompt: String?) -> String {
        guard let systemPrompt, !systemPrompt.isEmpty else { return text }
        return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(text)<|im_end|>\n<|im_start|>assistant\n"
    }
}

private enum ETImageDecoder {
    static func decodeImage(fromPath path: String) throws -> Image {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let imageRef = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "Noema.ExecuTorch", code: -1100, userInfo: [NSLocalizedDescriptionKey: "Unable to decode image at \(path)."])
        }

        let width = imageRef.width
        let height = imageRef.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8

        var raw = Data(count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let drawSucceeded = raw.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            guard let ctx = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            ctx.draw(imageRef, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drawSucceeded else {
            throw NSError(domain: "Noema.ExecuTorch", code: -1101, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare image tensor bytes for \(path)."])
        }

        return Image(data: raw, width: width, height: height, channels: bytesPerPixel)
    }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
extension AnyLLMClient {
    init(_ client: ExecuTorchLLMClient) {
        self.init(
            textStream: { input in
                try await client.textStream(from: input)
            },
            cancel: {
                Task { await client.cancelActive() }
            },
            unload: {
                Task { await client.unload() }
            },
            reset: {
                await client.hardResetConversation()
            }
        )
    }
}
#else
@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
final actor ExecuTorchLLMClient {
    private static let unsupportedMessage = "ExecuTorch is unavailable on this platform in the current build."

    init(modelPath: String, tokenizerPath: String, isVision: Bool, settings: ModelSettings) {}

    func load() async throws {
        throw NSError(
            domain: "Noema.ExecuTorch",
            code: -2000,
            userInfo: [NSLocalizedDescriptionKey: Self.unsupportedMessage]
        )
    }

    func unload() {}
    func cancelActive() {}
    func resetConversation() {}
    func hardResetConversation() {}
    func setSystemPrompt(_ prompt: String?) {}
    func syncSystemPrompt(_ prompt: String?) {}

    func textStream(from input: LLMInput) async throws -> AsyncThrowingStream<String, Error> {
        throw NSError(
            domain: "Noema.ExecuTorch",
            code: -2000,
            userInfo: [NSLocalizedDescriptionKey: Self.unsupportedMessage]
        )
    }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
extension AnyLLMClient {
    init(_ client: ExecuTorchLLMClient) {
        self = .makeFailing(message: "ExecuTorch is unavailable on this platform in the current build.")
    }
}
#endif
