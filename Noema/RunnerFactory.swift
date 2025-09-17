// RunnerFactory.swift
import Foundation
import LeapSDK
// Removed LocalLLMClient import in favor of mlx-swift integration
// Using our own llama.cpp implementation instead of LocalLLMClientLlama
import enum Noema.ModelFormat

enum Runner {
    case leap(any ModelRunner)
    case llm(AnyLLMClient)
}

enum RunnerFactory {
    static func load(url: URL, format: ModelFormat) async throws -> Runner {
        switch format {
        case .gguf:
            return .llm(try await AnyLLMClient(
                NoemaLlamaClient.llama(url: url)
            ))
        case .mlx:
            // Route MLX models to text or VLM backend based on config
            if MLXBridge.isVLMModel(at: url) {
                return .llm(try await MLXBridge.makeVLMClient(url: url))
            } else {
                return .llm(try await MLXBridge.makeTextClient(url: url, settings: nil))
            }
        case .slm:
            return .leap(try await Leap.load(url: url))
        case .apple:
            // Unsupported model format in this build.
            throw NSError(domain: "Noema", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unsupported model format"])
        }
    }
}
