// RunnerFactory.swift
import Foundation
#if canImport(LeapSDK)
import LeapSDK
#endif
// Removed LocalLLMClient import in favor of mlx-swift integration
// Using our own llama.cpp implementation instead of LocalLLMClientLlama

enum Runner {
#if canImport(LeapSDK)
    case leap(any ModelRunner)
#endif
    case llm(AnyLLMClient)
}

enum RunnerFactory {
    static func load(url: URL, format: ModelFormat) async throws -> Runner {
        switch format {
        case .gguf:
            // Prefer explicit projector if present next to the weights
            let mmproj = ProjectorLocator.projectorPath(alongside: url)
            let param = LlamaParameter(options: LlamaOptions(), contextLength: nil, threadCount: nil, mmproj: mmproj)
            return .llm(try await AnyLLMClient(
                NoemaLlamaClient.llama(url: url, parameter: param)
            ))
        case .mlx:
            // Route MLX models to text or VLM backend based on config
            if MLXBridge.isVLMModel(at: url) {
                return .llm(try await MLXBridge.makeVLMClient(url: url))
            } else {
                return .llm(try await MLXBridge.makeTextClient(url: url, settings: nil))
            }
        case .slm:
#if canImport(LeapSDK)
            LeapBundleDownloader.sanitizeBundleIfNeeded(at: url)
            return .leap(try await Leap.load(url: url))
#else
            throw NSError(
                domain: "Noema",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "SLM models are not supported on this platform."]
            )
#endif
        case .apple:
            // Unsupported model format in this build.
            throw NSError(domain: "Noema", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unsupported model format"])
        }
    }
}
