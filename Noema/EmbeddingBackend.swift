// EmbeddingBackend.swift
import Foundation

enum EmbeddingError: Error, LocalizedError {
    case modelMissing
    case notConfigured
    case loadFailed(String)
    case embedFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "Embedding model file missing"
        case .notConfigured: return "Embedding backend not loaded"
        case .loadFailed(let s): return "Failed to load embeddings backend: \(s)"
        case .embedFailed: return "Failed to compute embeddings"
        }
    }
}

enum EmbeddingTask {
    case generic
    case searchQuery
    case searchDocument

    var prefix: String? {
        switch self {
        case .generic: return nil
        case .searchQuery: return "search_query:"
        case .searchDocument: return "search_document:"
        }
    }
}

enum EmbeddingPooling {
    case none
}

protocol EmbeddingsBackend: AnyObject {
    var isReady: Bool { get }
    var dimension: Int { get }

    func load() throws
    func warmUp() throws
    func countTokens(_ text: String) throws -> Int
    func embed(
        _ texts: [String],
        task: EmbeddingTask,
        pooling: EmbeddingPooling,
        normalize: Bool
    ) throws -> [[Float]]
    /// Unload/free any native resources and stop background work. After this call
    /// the backend should be considered unusable until `load()` is called again.
    func unload()
}


