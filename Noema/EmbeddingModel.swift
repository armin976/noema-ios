// EmbeddingModel.swift
import Foundation

actor EmbeddingModel {
    static let shared = EmbeddingModel()
    
    // llama backend
    private var backend: EmbeddingsBackend?
    private(set) var warmedUp = false
    private var isLoading = false
    // Track active embedding operations that should keep the backend alive
    private var activeOperations: Int = 0

    /// Public read accessor for active operation count. Accessing this is async because
    /// the value is actor-isolated; callers should `await EmbeddingModel.shared.activeOperationsCount`.
    var activeOperationsCount: Int {
        return activeOperations
    }

    // Paths per spec – always load from our app Documents sandbox
    static let modelDir: URL = {
        var url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        url.appendPathComponent("LocalLLMModels/Embeddings/nomic-ai/nomic-embed-text-v1.5", isDirectory: true)
        return url
    }()
    static let modelFilename = "nomic-embed-text-v1.5.Q4_K_M.gguf"
    static var modelURL: URL { modelDir.appendingPathComponent(modelFilename) }

    private init() {}

    // Cheap prep only – no network
    func ensureModel() async { try? FileManager.default.createDirectory(at: Self.modelDir, withIntermediateDirectories: true) }

    func load() throws {
        guard FileManager.default.fileExists(atPath: Self.modelURL.path) else { 
            Task { await logger.log("[EmbedModel] ❌ Model file not found at: \(Self.modelURL.path)") }
            throw EmbeddingError.modelMissing 
        }
        
        // Ensure we don't already have a backend loaded
        if let existingBackend = backend {
            Task { await logger.log("[EmbedModel] ⚠️ Backend already loaded, unloading first") }
            backend = nil
            warmedUp = false
        }
        
        let b = LlamaEmbeddingBackend(modelPath: Self.modelURL.path)
        do {
            try b.load()
            backend = b
            Task { await logger.log("[EmbedModel] ✅ Backend loaded successfully") }
        } catch {
            backend = nil
            warmedUp = false
            Task { await logger.log("[EmbedModel] ❌ Failed to load backend: \(error.localizedDescription)") }
            throw error
        }
    }

    func unload() {
        if let b = backend {
            Task.detached { await logger.log("[EmbedModel] Unloading embedding backend") }
            b.unload()
            backend = nil
            warmedUp = false
        }
    }

    func warmUp() async {
        if backend == nil {
            if FileManager.default.fileExists(atPath: Self.modelURL.path) {
                do { try load() } catch { warmedUp = false; return }
            } else { warmedUp = false; return }
        }
        do {
            try backend?.warmUp()
            warmedUp = backend?.isReady ?? false
        } catch {
            Task { await logger.log("[Embed] ❌ warmUp failed: \(error.localizedDescription)") }
            warmedUp = false
        }
    }

    func isReady() -> Bool { warmedUp }

    func isModelAvailable() -> Bool { FileManager.default.fileExists(atPath: Self.modelURL.path) }

    func countTokens(_ text: String) async -> Int {
        do { if backend == nil { try load() }; return try backend?.countTokens(text) ?? text.split{ $0.isWhitespace }.count }
        catch { return text.split{ $0.isWhitespace }.count }
    }

    func embed(_ text: String) async -> [Float] {
        do { if backend == nil { try load() }; return try backend?.embed([text], task: .generic, pooling: .none, normalize: true).first ?? [] }
        catch { return [] }
    }

    // Preferred specialized variants for better retrieval quality with models like nomic-embed-text-v2
    func embedDocuments(_ texts: [String]) async -> [[Float]] {
        guard !texts.isEmpty else {
            Task.detached { await logger.log("[EmbedModel] embedDocuments called with empty array") }
            return []
        }
        do {
            // Ensure backend is loaded; serialize load using isLoading flag to prevent racing callers
            if backend == nil {
                if isLoading {
                    // Wait briefly for an in-flight load to complete
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                if backend == nil {
                    isLoading = true
                    Task.detached { await logger.log("[EmbedModel] Loading embedding backend for batch document embedding") }
                    defer { isLoading = false }
                    try load()
                }
            }
            guard let backend = backend else {
                Task.detached { await logger.log("[EmbedModel] embedDocuments: backend missing after load attempt") }
                return []
            }
            if !(backend.isReady) {
                // Attempt a warmUp once
                await warmUp()
            }
            guard backend.isReady else {
                Task.detached { await logger.log("[EmbedModel] embedDocuments: backend not ready") }
                return []
            }
            // Mark active operation while embedding so callers can coordinate unloads
            activeOperations += 1
            defer { activeOperations = max(0, activeOperations - 1) }

            // Try specialized task first
            do {
                return try backend.embed(texts, task: .searchDocument, pooling: .none, normalize: true)
            } catch {
                Task.detached { await logger.log("[EmbedModel] embedDocuments: searchDocument failed, falling back to generic – \(error.localizedDescription)") }
                // Fallback to generic
                return try backend.embed(texts, task: .generic, pooling: .none, normalize: true)
            }
        } catch {
            Task.detached { await logger.log("[EmbedModel] embedDocuments failed: \(error.localizedDescription)") }
            return []
        }
    }

    /// Batching with progress callback so UI can update continuously even if user navigates away
    func embedDocumentsWithProgress(_ texts: [String], onProgress: @escaping @Sendable (Int, Int) -> Void) async -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        do {
            if backend == nil { try load() }
            guard let backend = backend as? LlamaEmbeddingBackend else {
                // If backend is not our llama backend, fall back to regular embedding
                return await embedDocuments(texts)
            }
            if !backend.isReady { await warmUp() }
            guard backend.isReady else { return [] }
            // Keep track of an active embedding operation while this method runs
            activeOperations += 1
            defer { activeOperations = max(0, activeOperations - 1) }

            return try backend.embedWithProgress(texts, task: .searchDocument, pooling: .none, normalize: true) { done, total in
                Task { await logger.log("[Embed] Progress: \(done)/\(total)") }
                onProgress(done, total)
            }
        } catch {
            Task.detached { await logger.log("[EmbedModel] embedDocumentsWithProgress failed: \(error.localizedDescription)") }
            return []
        }
    }

    func embedDocument(_ text: String) async -> [Float] {
        // Guard against invalid input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Task.detached { await logger.log("[EmbedModel] embedDocument called with empty text") }
            return []
        }
        
        let results = await embedDocuments([text])
        if let first = results.first, !first.isEmpty {
            Task.detached { await logger.log("[EmbedModel] embedDocument: success, embedding dim=\(first.count)") }
            return first
        }
        return []

    } // end embedDocument

    func embedQuery(_ text: String) async -> [Float] {
        // Guard against invalid input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Task.detached { await logger.log("[EmbedModel] embedQuery called with empty text") }
            return []
        }
        
        do { 
            if backend == nil {
                if isLoading {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                if backend == nil {
                    isLoading = true
                    Task.detached { await logger.log("[EmbedModel] Loading embedding backend for query embedding") }
                    defer { isLoading = false }
                    try load()
                }
            }
            guard let backend = backend else {
                Task.detached { await logger.log("[EmbedModel] embedQuery: backend missing after load attempt") }
                return []
            }
            if !backend.isReady { await warmUp() }
            guard backend.isReady else {
                Task.detached { await logger.log("[EmbedModel] embedQuery: backend not ready") }
                return []
            }
            let result = try backend.embed([text], task: .searchQuery, pooling: .none, normalize: true).first ?? []
            Task.detached { await logger.log("[EmbedModel] embedQuery: success, embedding dim=\(result.count)") }
            return result
        } catch { 
            Task.detached { await logger.log("[EmbedModel] embedQuery failed: \(error.localizedDescription)") }
            // Do not reset backend here; simply report failure
            return [] 
        }
    }
}


