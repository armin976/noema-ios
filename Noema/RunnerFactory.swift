// RunnerFactory.swift
import Foundation
// Removed LocalLLMClient import in favor of mlx-swift integration
// Using our own llama.cpp implementation instead of LocalLLMClientLlama

enum Runner {
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
        case .et:
            guard #available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *) else {
                throw NSError(
                    domain: "Noema",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "ET models are not supported on this platform."]
                )
            }
            guard let pte = ETModelResolver.pteURL(for: url) else {
                throw NSError(domain: "Noema", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing .pte file for ET model."])
            }
            guard let tokenizer = ETModelResolver.tokenizerURL(for: url) ?? ETModelResolver.tokenizerURL(for: pte.deletingLastPathComponent()) else {
                throw NSError(domain: "Noema", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing tokenizer for ET model."])
            }
            let settings = ModelSettings.default(for: .et)
            let client = ExecuTorchLLMClient(
                modelPath: pte.path,
                tokenizerPath: tokenizer.path,
                isVision: false,
                settings: settings
            )
            try await client.load()
            return .llm(AnyLLMClient(client))
        case .ane:
            #if os(iOS) || os(visionOS)
            guard #available(iOS 18.0, visionOS 2.0, *) else {
                throw NSError(
                    domain: "Noema",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "CML models require iOS 18 or visionOS 2."]
                )
            }
            let resolved = try ANEModelResolver.resolve(modelURL: url)
            let client = try CoreMLLLMClient(resolvedModel: resolved, settings: .default(for: .ane))
            try await client.load()
            return .llm(AnyLLMClient(client))
            #else
            throw NSError(
                domain: "Noema",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "CML models are supported only on iOS and visionOS."]
            )
            #endif
        case .afm:
            let afmClient = AFMLLMClient()
            try await afmClient.load()
            return .llm(
                AnyLLMClient(
                    textStream: { input in
                        try await afmClient.textStream(from: input)
                    },
                    cancel: nil,
                    unload: { afmClient.unload() },
                    syncSystemPrompt: { prompt in
                        await afmClient.syncSystemPrompt(prompt)
                    }
                )
            )
        }
    }
}
