import Foundation

protocol ChatStreamingProviding {
    func stream(prompt: String, model: LocalModel?) async throws -> AsyncThrowingStream<TokenEvent, Error>
    var requiresModel: Bool { get }
}

enum ChatViewModelError: LocalizedError {
    case missingModel

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return "Load a model before starting a chat."
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id: UUID
        let role: Role
        var text: String
        var isStreaming: Bool

        init(id: UUID = UUID(), role: Role, text: String, isStreaming: Bool) {
            self.id = id
            self.role = role
            self.text = text
            self.isStreaming = isStreaming
        }
    }

    struct AlertInfo: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    enum Phase: Equatable {
        case idle
        case preparing
        case streaming(Progress)
    }

    struct Progress: Equatable {
        let startedAt: Date
        let tokenCount: Int
        let firstTokenAt: Date?
        let lastUpdate: Date

        var elapsed: TimeInterval { lastUpdate.timeIntervalSince(startedAt) }
        var tokensPerSecond: Double? {
            let duration = elapsed
            guard duration > 0, tokenCount > 0 else { return nil }
            return Double(tokenCount) / duration
        }
        var firstTokenDelay: TimeInterval? {
            guard let firstTokenAt else { return nil }
            return firstTokenAt.timeIntervalSince(startedAt)
        }
    }

    @Published private(set) var messages: [Message] = []
    @Published var input: String = ""
    @Published private(set) var phase: Phase = .idle
    @Published var alert: AlertInfo?

    private let modelManager: AppModelManager
    private let streamingProvider: ChatStreamingProviding
    private var streamTask: Task<Void, Never>?
    private var currentStreamID: UUID?

    init(modelManager: AppModelManager, streamingProvider: ChatStreamingProviding = DefaultChatStreamingProvider()) {
        self.modelManager = modelManager
        self.streamingProvider = streamingProvider
    }

    deinit {
        streamTask?.cancel()
    }

    var isStreaming: Bool {
        if case .streaming = phase { return true }
        return false
    }

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    var statusText: String? {
        guard case .streaming(let progress) = phase else { return nil }
        guard progress.elapsed > 0.4 else { return nil }
        var parts: [String] = [String(format: "%.1fs", progress.elapsed)]
        if let delay = progress.firstTokenDelay {
            parts.append(String(format: "ttfb %.0f ms", delay * 1000))
        }
        if let rate = progress.tokensPerSecond {
            parts.append(String(format: "%.1f tok/s", rate))
        }
        return parts.joined(separator: " · ")
    }

    func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        input = ""
        Task { await run(prompt: trimmed) }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        currentStreamID = nil
        phase = .idle
        if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[idx].isStreaming = false
            if messages[idx].text.isEmpty {
                messages[idx].text = "(stopped)"
            }
        }
    }

    private func run(prompt: String) async {
        streamTask?.cancel()
        streamTask = nil
        let userMessage = Message(role: .user, text: prompt, isStreaming: false)
        messages.append(userMessage)

        let assistantIndex = messages.count
        messages.append(Message(role: .assistant, text: "", isStreaming: true))

        let activeModel = modelManager.loadedModel ?? modelManager.lastUsedModel
        if streamingProvider.requiresModel && activeModel == nil {
            messages.removeLast()
            alert = AlertInfo(message: ChatViewModelError.missingModel.localizedDescription ?? "Load a model first.")
            return
        }

        let streamID = UUID()
        currentStreamID = streamID
        phase = .preparing

        do {
            let stream = try await streamingProvider.stream(prompt: prompt, model: activeModel)
            beginStreaming(stream, streamID: streamID, messageIndex: assistantIndex)
        } catch {
            currentStreamID = nil
            messages.removeLast()
            alert = AlertInfo(message: presentable(error))
        }
    }

    private func beginStreaming(_ stream: AsyncThrowingStream<TokenEvent, Error>, streamID: UUID, messageIndex: Int) {
        let start = Date()
        phase = .streaming(Progress(startedAt: start, tokenCount: 0, firstTokenAt: nil, lastUpdate: start))
        streamTask = Task { [weak self] in
            var tokenCount = 0
            var firstTokenAt: Date?
            do {
                for try await event in stream {
                    guard let self else { return }
                    if Task.isCancelled { return }
                    guard case .token(let fragment) = event else { continue }
                    tokenCount += 1
                    if firstTokenAt == nil { firstTokenAt = Date() }
                    await MainActor.run {
                        guard self.currentStreamID == streamID else { return }
                        guard self.messages.indices.contains(messageIndex) else { return }
                        self.messages[messageIndex].text.append(fragment)
                        self.messages[messageIndex].isStreaming = true
                        let now = Date()
                        let progress = Progress(startedAt: start, tokenCount: tokenCount, firstTokenAt: firstTokenAt, lastUpdate: now)
                        self.phase = .streaming(progress)
                    }
                }
                await MainActor.run {
                    guard let self = self else { return }
                    guard self.currentStreamID == streamID else { return }
                    guard self.messages.indices.contains(messageIndex) else { return }
                    self.messages[messageIndex].isStreaming = false
                    self.phase = .idle
                    self.currentStreamID = nil
                    self.streamTask = nil
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self = self else { return }
                    guard self.currentStreamID == streamID else { return }
                    if self.messages.indices.contains(messageIndex) {
                        self.messages[messageIndex].isStreaming = false
                        if self.messages[messageIndex].text.isEmpty {
                            self.messages[messageIndex].text = "⚠️ \(self.presentable(error))"
                        }
                    }
                    self.phase = .idle
                    self.currentStreamID = nil
                    self.streamTask = nil
                    self.alert = AlertInfo(message: self.presentable(error))
                }
            }
        }
    }

    private func presentable(_ error: Error) -> String {
        if let appError = error as? AppError {
            return ErrorPresenter.present(appError)
        }
        let nsError = error as NSError
        if let appError = nsError.userInfo[NSUnderlyingErrorKey] as? AppError {
            return ErrorPresenter.present(appError)
        }
        if let message = (error as? LocalizedError)?.errorDescription {
            return message
        }
        return nsError.localizedDescription
    }
}

final class DefaultChatStreamingProvider: ChatStreamingProviding {
    let requiresModel: Bool

    private var router = BackendRouter()
    private var cachedModelID: String?
    private var backend: (any InferenceBackend)?

    init(processInfo: ProcessInfo = .processInfo) {
        requiresModel = !processInfo.arguments.contains("CHAT_SMOKE_FAKE")
    }

    func stream(prompt: String, model: LocalModel?) async throws -> AsyncThrowingStream<TokenEvent, Error> {
        if !requiresModel {
            return Self.mockStream(for: prompt)
        }
        guard let model else {
            throw ChatViewModelError.missingModel
        }
        if cachedModelID != model.id || backend == nil {
            let installed = Self.makeInstalledModel(from: model)
            backend = try await router.open(model: installed)
            cachedModelID = model.id
        }
        guard let backend else {
            throw ChatViewModelError.missingModel
        }
        return backend.generate(streaming: GenerateRequest(prompt: prompt))
    }

    private static func makeInstalledModel(from model: LocalModel) -> InstalledModel {
        let size = (try? model.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        return InstalledModel(
            modelID: model.modelID,
            quantLabel: model.quant,
            url: model.url,
            format: model.format,
            sizeBytes: size,
            lastUsed: model.lastUsedDate,
            installDate: model.downloadDate,
            checksum: nil,
            isFavourite: model.isFavourite,
            totalLayers: model.totalLayers,
            isMultimodal: model.isMultimodal,
            isToolCapable: model.isToolCapable
        )
    }

    private static func mockStream(for prompt: String) -> AsyncThrowingStream<TokenEvent, Error> {
        let chunks = ["Mock", " answer", " to", " \"", prompt, "\""]
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    continuation.yield(.token(chunk))
                }
                continuation.finish()
            }
        }
    }
}
