// LlamaEmbeddingBackend.swift
import Foundation

final class LlamaEmbeddingBackend: EmbeddingsBackend {
    private let modelPath: String
    private var embedder: LlamaEmbedder?
    private(set) var dimension: Int = 0
    var isReady: Bool { (embedder?.isReady() ?? false) && dimension > 0 }

    init(modelPath: String) { self.modelPath = modelPath }

    func load() throws {
        guard FileManager.default.fileExists(atPath: modelPath) else { throw EmbeddingError.modelMissing }

        // Reasonable defaults for iOS
        let pathMsg = "[Embed] load_model path=\(modelPath)"
        Task.detached(priority: .utility) { await logger.log(pathMsg) }
        let threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        Task.detached(priority: .utility) { await logger.log("[Embed] Using \(threadCount) threads") }

        let desiredGpuLayers: Int32 = {
#if canImport(Metal)
            return 1_000_000 // Request full offload when GPU is available
#else
            return 0
#endif
        }()

        let threads32 = Int32(threadCount)
        var loadedWithGPU = false
        var resolvedEmbedder: LlamaEmbedder?

#if canImport(Metal)
        if DeviceGPUInfo.supportsGPUOffload && desiredGpuLayers > 0 {
            Task.detached(priority: .utility) { await logger.log("[Embed] Attempting GPU offload with nGpuLayers=\(desiredGpuLayers)") }
            let gpuEmbedder = LlamaEmbedder(
                modelPath: modelPath,
                threads: threads32,
                nGpuLayers: desiredGpuLayers
            )

            if gpuEmbedder.isReady() {
                resolvedEmbedder = gpuEmbedder
                loadedWithGPU = true
            } else {
                Task.detached(priority: .utility) { await logger.log("[Embed] ⚠️ GPU offload failed, falling back to CPU") }
                gpuEmbedder.unload()
            }
        }
#endif

        if resolvedEmbedder == nil {
            let cpuEmbedder = LlamaEmbedder(
                modelPath: modelPath,
                threads: threads32,
                nGpuLayers: 0
            )

            guard cpuEmbedder.isReady() else {
                Task.detached(priority: .utility) { await logger.log("[Embed] ❌ Failed to load embedder on CPU") }
                throw EmbeddingError.loadFailed("embedder init failed on CPU")
            }

            resolvedEmbedder = cpuEmbedder
        }

        guard let resolvedEmbedder else {
            throw EmbeddingError.loadFailed("embedder init unresolved")
        }

        embedder = resolvedEmbedder
        dimension = Int(resolvedEmbedder.dimension())
        let dim = dimension
        Task.detached(priority: .utility) {
            let backend = loadedWithGPU ? "GPU" : "CPU"
            await logger.log("[Embed] ✅ Model loaded successfully (\(backend)), dim=\(dim), threads=\(threadCount)")
        }
    }

    func warmUp() throws {
        guard let embedder else { throw EmbeddingError.notConfigured }
        let dim = Int(embedder.dimension())
        guard dim > 0 else {
            throw EmbeddingError.loadFailed("invalid embedding dim during warmup")
        }
        let msg = "[Embed] warmup completed, model ready dim=\(dim)"
        Task.detached(priority: .utility) { await logger.log(msg) }
    }

    func countTokens(_ text: String) throws -> Int {
        guard let embedder else { throw EmbeddingError.notConfigured }
        return Int(embedder.countTokens(text))
    }

    func embed(_ texts: [String], task: EmbeddingTask, pooling: EmbeddingPooling, normalize: Bool) throws -> [[Float]] {
        guard let embedder else { 
            Task.detached(priority: .utility) { await logger.log("[Embed] ❌ embed() called but model/context not configured") }
            throw EmbeddingError.notConfigured 
        }
        if texts.isEmpty { return [] }
        
        let dim = Int(embedder.dimension())
        guard dim > 0 else {
            Task.detached(priority: .utility) { await logger.log("[Embed] ❌ Invalid dimension: \(dim)") }
            throw EmbeddingError.embedFailed
        }
        
        Task.detached(priority: .utility) { await logger.log("[Embed] Starting embedding for \(texts.count) text(s), dim=\(dim)") }
        // Adjust batch size heuristics (controlled by caller). Here we log the type of task.
        switch task {
        case .searchDocument: Task.detached(priority: .utility) { await logger.log("[Embed] task=searchDocument pooling=\(pooling) normalize=\(normalize)") }
        case .searchQuery: Task.detached(priority: .utility) { await logger.log("[Embed] task=searchQuery pooling=\(pooling) normalize=\(normalize)") }
        case .generic: Task.detached(priority: .utility) { await logger.log("[Embed] task=generic pooling=\(pooling) normalize=\(normalize)") }
        }
        
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        
        for (index, t) in texts.enumerated() {
            if Task.isCancelled { break }
            do {
                let s: String
                if let prefix = task.prefix { s = prefix + " " + t } else { s = t }
                
                // Validate input text
                guard !s.isEmpty && s.count < 8192 else {
                    Task.detached(priority: .utility) { await logger.log("[Embed] ❌ Invalid text length: \(s.count)") }
                    throw EmbeddingError.embedFailed
                }
                
                var vec = Array(repeating: Float(0), count: Int(dim))
                let ok = vec.withUnsafeMutableBufferPointer { buf -> Bool in
                    guard let base = buf.baseAddress else { return false }
                    // Ensure the embedder returns mean-pooled sentence embeddings
                    return embedder.embedText(s, intoBuffer: base, length: Int32(dim))
                }
                if !ok {
                    Task.detached(priority: .utility) { await logger.log("[Embed] ❌ Embedding failed for text \(index)") }
                    throw EmbeddingError.embedFailed
                }
                
                if normalize {
                    let n = sqrt(vec.reduce(0) { $0 + $1 * $1 })
                    if n > 0 { for i in 0..<vec.count { vec[i] /= Float(n) } }
                }
                results.append(vec)
                
                // Log progress for longer sequences
                if texts.count > 1 {
                    Task.detached(priority: .utility) { await logger.log("[Embed] Progress: \(index + 1)/\(texts.count)") }
                }
                
            } catch {
                Task.detached(priority: .utility) { await logger.log("[Embed] ❌ Exception during embedding text \(index): \(error.localizedDescription)") }
                throw error
            }
        }
        
        Task.detached(priority: .utility) { await logger.log("[Embed] ✅ Successfully embedded \(results.count) text(s) [mean pooling]") }
        return results
    }

    /// Embeds texts and invokes a callback after each item is produced.
    /// - Parameters:
    ///   - texts: Input texts to embed
    ///   - task: Embedding task flavor
    ///   - pooling: Pooling behavior (unused for this backend)
    ///   - normalize: Whether to L2-normalize vectors
    ///   - onItem: Callback receiving (completedCount, totalCount)
    /// - Returns: Array of vectors, one per input text
    func embedWithProgress(
        _ texts: [String],
        task: EmbeddingTask,
        pooling: EmbeddingPooling,
        normalize: Bool,
        onItem: (Int, Int) -> Void
    ) throws -> [[Float]] {
        let total = texts.count
        var results: [[Float]] = []
        results.reserveCapacity(total)
        for (index, t) in texts.enumerated() {
            if Task.isCancelled { break }
            let vecs = try embed([t], task: task, pooling: pooling, normalize: normalize)
            if let v = vecs.first { results.append(v) } else { results.append([]) }
            onItem(index + 1, total)
            if Task.isCancelled { break }
        }
        return results
    }

    deinit {
        embedder?.unload()
    }

    func unload() {
        embedder?.unload()
        embedder = nil
        dimension = 0
        Task.detached(priority: .utility) { await logger.log("[Embed] Backend unloaded and freed from memory") }
    }
}


