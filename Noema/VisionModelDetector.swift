// VisionModelDetector.swift
import Foundation

enum VisionModelDetector {
    static func isVisionModel(repoId: String, token: String?) async -> Bool {
        // Only check the pipeline tag via the Hub API
        return await hubApiSuggestsVision(repoId: repoId, token: token)
    }
    
    static func isVisionModelCachedOrHeuristic(repoId: String) -> Bool {
        if let cached = HuggingFaceMetadataCache.cached(repoId: repoId) {
            if cached.isVision { return true }
        }
        // Heuristic: repo id contains known vision keywords
        let lower = repoId.lowercased()
        if lower.contains("-vl-") || lower.contains("-vlm") || lower.contains("vision") || lower.contains("image-text-to-text") {
            return true
        }
        return false
    }
    
    private static func hubApiSuggestsVision(repoId: String, token: String?) async -> Bool {
        if let cached = HuggingFaceMetadataCache.cached(repoId: repoId) {
            if cached.isVision { return true }
        }
        if let meta = await HuggingFaceMetadataCache.fetchAndCache(repoId: repoId, token: token) {
            return meta.isVision
        }
        return false
    }
    private static func resolvedURL(repoId: String, file: String) -> String {
        // Use resolve/main path which handles LFS and pointers transparently
        // Ensure proper URL encoding of repoId
        let escaped = repoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoId
        return "https://huggingface.co/\(escaped)/resolve/main/\(file)"
    }
    
    private static func fetch(_ urlStr: String, token: String?) async -> Data? {
        guard let url = URL(string: urlStr) else { return nil }
        do {
            let (data, resp) = try await HFHubRequestManager.shared.data(for: url,
                                                                         token: token,
                                                                         accept: nil,
                                                                         timeout: 6)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) { return data }
        } catch { }
        return nil
    }
    
    private static func readmeContainsVisionHints(_ text: String) -> Bool {
        let visionKeywords = [
            "<|image|>", "<image>", "multimodal", "vision", "visual", "vlm",
            "image-to-text", "image understanding", "visual question answering",
            "computer vision", "image analysis", "image captioning",
            "visual instruction", "visual chat", "see images", "image input"
        ]
        return visionKeywords.contains { text.contains($0) }
    }
    
    private static func fetchResolved(repoId: String, file: String, token: String?) async -> Data? {
        let url = resolvedURL(repoId: repoId, file: file)
        return await fetch(url, token: token)
    }
}


