// LeapCatalogService.swift
// Legacy compatibility shim for ET model metadata helpers.

import Foundation

enum LeapCatalogService {
    static func name(for modelID: String) -> String? {
        let repo = modelID.split(separator: "/").last.map(String.init) ?? modelID
        let cleaned = repo
            .replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func isVisionQuantizationSlug(_ slug: String) -> Bool {
        let lower = slug.lowercased()
        let tokens = [
            "vision", "vlm", "llava", "qwen-vl", "qwen2-vl", "qwen3-vl",
            "multimodal", "image", "pixtral", "minicpm-v", "gemma-vision"
        ]
        return tokens.contains { lower.contains($0) }
    }

    static func bundleLikelyVision(at url: URL) -> Bool {
        let lowerPath = url.path.lowercased()
        if isVisionQuantizationSlug(lowerPath) {
            return true
        }

        let dir: URL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            dir = url
        } else {
            dir = url.deletingLastPathComponent()
        }

        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return false
        }

        for file in files {
            let name = file.lastPathComponent.lowercased()
            if isVisionQuantizationSlug(name) { return true }
            if name.contains("projector") || name.contains("mmproj") || name.contains("image") { return true }
            if name == "preprocessor_config.json" { return true }
        }
        return false
    }
}
