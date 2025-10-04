// ModelSettings.swift
import Foundation
import SwiftUI
enum CacheQuant: String, Codable, CaseIterable, Identifiable {
    case f32 = "F32"
    case f16 = "F16"
    case q8_0 = "Q8_0"
    case q5_0 = "Q5_0"
    case q5_1 = "Q5_1"
    case q4_0 = "Q4_0"
    case q4_1 = "Q4_1"
    case iq4_nl = "IQ4_NL"

    var id: String { rawValue }
}

struct ModelSettings: Codable, Equatable {
    var contextLength: Double = 4096
    // -1 means: auto/offload all available layers (default). 0+ means explicit override
    var gpuLayers: Int = -1
    var cpuThreads: Int = 0
    var kvCacheOffload: Bool = true
    var keepInMemory: Bool = true
    var useMmap: Bool = true
    var flashAttention: Bool = false
    var seed: Int?
    var kCacheQuant: CacheQuant = .f16
    var vCacheQuant: CacheQuant = .f16
    /// Optional tokenizer path to override default
    var tokenizerPath: String?
    /// Optional prompt template for chat models
    var promptTemplate: String?
    // Sampling parameters for generation (used by MLX and others)
    var temperature: Double = 0.7
    var repetitionPenalty: Float = 1.1
    var topK: Int = 40
    var topP: Double = 0.95

    static func `default`(for format: ModelFormat) -> ModelSettings {
        var s = ModelSettings()
        switch format {
        case .mlx:
            s.gpuLayers = 0
            s.cpuThreads = ProcessInfo.processInfo.activeProcessorCount
        case .gguf, .slm:
            s.cpuThreads = ProcessInfo.processInfo.activeProcessorCount
        case .apple:
            s.cpuThreads = ProcessInfo.processInfo.activeProcessorCount
        }
        s.tokenizerPath = nil
        s.promptTemplate = nil
        return s
    }

    /// Creates settings from a model's config.json if present.
    /// Falls back to sensible defaults when the config is missing.
    static func fromConfig(for model: LocalModel) -> ModelSettings {
        var s = ModelSettings.default(for: model.format)
        let dir = model.url.deletingLastPathComponent()

        // PRIORITY 1: Curated architecture-specific templates for GGUF/MLX
        if let curated = ArchitectureTemplates.template(for: model) {
            s.promptTemplate = curated
            return s
        }

        // PRIORITY 2: Repo config.json chat_template
        let cfgURL = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: cfgURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let tmpl = json["chat_template"] as? String { s.promptTemplate = tmpl }
        }

        // PRIORITY 3: Tokenizer metadata
        if s.promptTemplate == nil {
            let tokCfg = dir.appendingPathComponent("tokenizer_config.json")
            if let data = try? Data(contentsOf: tokCfg),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tmpl = json["chat_template"] as? String {
                s.promptTemplate = tmpl
            }
        }
        if s.promptTemplate == nil {
            let tok = dir.appendingPathComponent("tokenizer.json")
            if let data = try? Data(contentsOf: tok),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tmpl = json["chat_template"] as? String {
                s.promptTemplate = tmpl
            }
        }

        // PRIORITY 4: GGUF embedded template
        if s.promptTemplate == nil && model.format == .gguf {
            var ggufURL = model.url
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: ggufURL.path, isDirectory: &isDir), isDir.boolValue {
                if let f = try? FileManager.default.contentsOfDirectory(at: ggufURL, includingPropertiesForKeys: nil)
                    .first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                    ggufURL = f
                }
            }
            if let tmpl = GGUFMetadata.chatTemplate(at: ggufURL) {
                s.promptTemplate = tmpl
            }
        }

        return s
    }
}
