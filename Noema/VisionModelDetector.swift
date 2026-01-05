// VisionModelDetector.swift
import Foundation

enum VisionModelDetector {
    static func isVisionModel(repoId: String, token: String?) async -> Bool {
        if let cached = cachedMeta(repoId: repoId) {
            if cached.isVision { return true }
        }
        let resolvedToken = normalizedToken(token)
        guard let meta = await HuggingFaceMetadataCache.fetchAndCache(repoId: repoId, token: resolvedToken) else {
            return false
        }
        return meta.isVision
    }

    static func isVisionModelCachedOrHeuristic(repoId: String) -> Bool {
        guard let cached = cachedMeta(repoId: repoId) else { return false }
        return cached.isVision
    }

    static func projectorMetadata(repoId: String, token: String?) async -> ModelHubMeta.ProjectorFile? {
        if let cached = cachedMeta(repoId: repoId),
           let files = cached.projectorFiles {
            return files.first
        }
        let resolvedToken = normalizedToken(token)
        let meta = await HuggingFaceMetadataCache.fetchAndCache(repoId: repoId, token: resolvedToken)
        return meta?.projectorFiles?.first
    }

    private static func cachedMeta(repoId: String) -> ModelHubMeta? {
        HuggingFaceMetadataCache.cached(repoId: repoId)
    }

    private static func normalizedToken(_ token: String?) -> String? {
        guard let token else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
