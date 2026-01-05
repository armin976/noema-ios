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
    var minP: Double = 0.0
    var repeatLastN: Int = 64
    var presencePenalty: Float = 0.0
    var frequencyPenalty: Float = 0.0
    /// Optional stop sequences sourced from repo-provided params files (applied on first use)
    var stopSequences: [String]? = nil
    var speculativeDecoding: SpeculativeDecodingSettings = .init()
    var ropeScaling: RopeScalingSettings? = nil
    var logitBias: [Int: Double] = [:]
    var promptCacheEnabled: Bool = false
    var promptCachePath: String = ""
    var promptCacheAll: Bool = false
    var tensorOverride: TensorOverridePreset = .none
    /// Optional override for the number of experts to use when running MoE models.
    var moeActiveExperts: Int? = nil

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

        // PRIORITY 5: Repo-specified sampling hints (params / params.json)
        if let paramsURL = Self.locateParamsFile(in: dir),
           let data = try? Data(contentsOf: paramsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            s.applyParamsJSON(obj)
        }

        return s
    }
}

private extension ModelSettings {
    /// Finds a params sidecar file (either `params` or `params.json`) in the given directory.
    static func locateParamsFile(in dir: URL) -> URL? {
        let fm = FileManager.default
        for name in ["params.json", "params"] {
            let cand = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: cand.path) { return cand }
        }
        return nil
    }

    /// Applies sampling defaults from a params JSON object. Unknown fields are ignored.
    mutating func applyParamsJSON(_ obj: [String: Any]) {
        func double(_ key: String) -> Double? {
            if let n = obj[key] as? NSNumber { return n.doubleValue }
            if let s = obj[key] as? String { return Double(s) }
            return nil
        }
        func int(_ key: String) -> Int? {
            if let n = obj[key] as? NSNumber { return n.intValue }
            if let s = obj[key] as? String, let v = Int(s) { return v }
            return nil
        }

        if let t = double("temperature") { temperature = t }
        if let k = int("top_k") { topK = max(1, k) }
        if let p = double("top_p") { topP = max(0.0, min(1.0, p)) }
        if let mp = double("min_p") { minP = max(0.0, min(1.0, mp)) }
        if let rp = double("repeat_penalty") { repetitionPenalty = Float(rp) }
        if let rl = int("repeat_last_n") { repeatLastN = max(0, rl) }
        if let pres = double("presence_penalty") { presencePenalty = Float(pres) }
        if let freq = double("frequency_penalty") { frequencyPenalty = Float(freq) }

        if let stop = obj["stop"] as? [String] {
            stopSequences = stop
        } else if let stopAny = obj["stop"] as? [Any] {
            stopSequences = stopAny.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else if let stopSingle = obj["stop"] as? String, !stopSingle.isEmpty {
            stopSequences = [stopSingle]
        }
    }
}

extension ModelSettings {
    struct SpeculativeDecodingSettings: Codable, Equatable {
        enum Mode: String, Codable, CaseIterable, Identifiable {
            case tokens
            case max

            var id: String { rawValue }
            var title: String {
                switch self {
                case .tokens: return "Draft Tokens"
                case .max: return "Draft Window"
                }
            }
        }

        var helperModelID: String? = nil
        var mode: Mode = .tokens
        var value: Int = 64

        var hasSelection: Bool { helperModelID != nil }
    }

    struct RopeScalingSettings: Codable, Equatable {
        var factor: Double = 1.0
        var originalContext: Int = 4096
        var lowFrequency: Double = 1.0
        var highFrequency: Double = 1.0
    }

    enum TensorOverridePreset: String, Codable, CaseIterable, Identifiable {
        case none
        case ffnCPU
        case expertsCPU

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "Default placement"
            case .ffnCPU: return "ffn=CPU (dense models)"
            case .expertsCPU: return "exps=CPU (MoE)"
            }
        }

        var overrideValue: String? {
            switch self {
            case .none: return nil
            case .ffnCPU: return "ffn=CPU"
            case .expertsCPU: return "exps=CPU"
            }
        }

        var requiresWarning: Bool {
            switch self {
            case .none:
                return false
            case .ffnCPU, .expertsCPU:
                return true
            }
        }
    }
}
