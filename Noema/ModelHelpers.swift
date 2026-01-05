// ModelHelpers.swift
import Foundation

extension String {
    /// Detects if a model name indicates it's a reasoning model
    var isReasoningModel: Bool {
        let lowercased = self.lowercased()
        let reasoningPatterns = [
            "o1-", "o1_",
            "deepseek-r1", "deepseek_r1",
            "qwq", "qwen-qwq", "qwen_qwq",
            "reasoning", "reasoner",
            "step-by-step", "stepbystep",
            "chain-of-thought", "chainofthought", "cot"
        ]
        
        return reasoningPatterns.contains { pattern in
            lowercased.contains(pattern)
        }
    }
}

extension LocalModel {
    /// Indicates if this is a reasoning model based on its name or ID
    var isReasoningModel: Bool {
        return name.isReasoningModel || modelID.isReasoningModel
    }
}

extension ModelRecord {
    /// Indicates if this is a reasoning model based on its name or ID
    var isReasoningModel: Bool {
        return displayName.isReasoningModel || id.isReasoningModel
    }
}

enum ModelVisionDetector {
    static func guessLlamaVisionModel(from url: URL) -> Bool {
        ProjectorLocator.hasProjectorFile(alongside: url)
    }
}

enum ProjectorLocator {
    private static let projectorKeywords = ["mmproj", "projector", "image_proj"]

    static func hasProjectorFile(alongside modelURL: URL) -> Bool {
        let directory = modelURL.deletingLastPathComponent()
        return hasProjectorFile(in: directory)
    }

    static func hasProjectorForModelID(_ modelID: String) -> Bool {
        let baseDir = InstalledModelsStore.baseDir(for: .gguf, modelID: modelID)
        return hasProjectorFile(in: baseDir)
    }

    static func hasProjectorFile(in directory: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        if contents.contains(where: isProjectorFile(_:)) {
            return true
        }
        for entry in contents {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue {
                if let subcontents = try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil),
                   subcontents.contains(where: isProjectorFile(_:)) {
                    return true
                }
            }
        }
        return false
    }

    private static func isProjectorFile(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "gguf" else { return false }
        let lowercased = url.lastPathComponent.lowercased()
        return projectorKeywords.contains { lowercased.contains($0) }
    }

    /// Returns the absolute path to a projector `.gguf` if we can resolve one next to the model.
    /// Resolution order:
    /// 1) `artifacts.json` key "mmproj" (sibling file)
    /// 2) First `.gguf` file in the same directory matching common projector keywords,
    ///    preferring F16/F32 variants when multiple are present.
    static func projectorPath(alongside modelURL: URL) -> String? {
        let dir: URL = {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDir), isDir.boolValue {
                return modelURL
            }
            return modelURL.deletingLastPathComponent()
        }()

        // Try artifacts.json hint first
        let artifactsURL = dir.appendingPathComponent("artifacts.json")
        if let data = try? Data(contentsOf: artifactsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rel = obj["mmproj"] as? String {
            let abs = dir.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: abs.path) { return abs.path }
        }

        // Fallback: scan directory for projector-like gguf files
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        let candidates = files.filter { isProjectorFile($0) }
        if candidates.isEmpty { return nil }
        // Prefer F16/F32 names if available
        if let hi = candidates.first(where: { name in
            let s = name.lastPathComponent.uppercased()
            return s.contains("F16") || s.contains("F32")
        }) {
            return hi.path
        }
        return candidates.first?.path
    }
}
