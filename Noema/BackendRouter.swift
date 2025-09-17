// BackendRouter.swift
import Foundation
import LeapSDK

struct GenerateRequest: Sendable { let prompt: String }
enum TokenEvent: Sendable { case token(String) }

protocol InferenceBackend {
    static var supported: Set<ModelFormat> { get }
    mutating func load(_ installed: InstalledModel) async throws
    func generate(streaming request: GenerateRequest) -> AsyncThrowingStream<TokenEvent, Error>
    mutating func unload()
}

struct LlamaBackend: InferenceBackend {
    static let supported: Set<ModelFormat> = [.gguf]
    private var client: NoemaLlamaClient?
    mutating func load(_ installed: InstalledModel) async throws {
        client = try await NoemaLlamaClient.llama(url: installed.url)
    }
    func generate(streaming request: GenerateRequest) -> AsyncThrowingStream<TokenEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let client = client else {
                continuation.finish(throwing: NSError(domain: "Noema", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "LlamaBackend client not loaded"]))
                return
            }
            
            Task {
                do {
                    let input = LLMInput.plain(request.prompt)
                    for try await token in try await client.textStream(from: input) {
                        continuation.yield(.token(token))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    mutating func unload() { client = nil }
}

struct MLXBackend: InferenceBackend {
    static let supported: Set<ModelFormat> = [.mlx]
    private var client: AnyLLMClient?
    mutating func load(_ installed: InstalledModel) async throws {
        if MLXBridge.isVLMModel(at: installed.url) {
            client = try await MLXBridge.makeVLMClient(url: installed.url)
        } else {
            client = try await MLXBridge.makeTextClient(url: installed.url, settings: nil)
        }
    }
    func generate(streaming request: GenerateRequest) -> AsyncThrowingStream<TokenEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let client = client else {
                continuation.finish(throwing: NSError(domain: "Noema", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "MLXBackend client not loaded"]))
                return
            }
            
            Task {
                do {
                    let input = LLMInput.plain(request.prompt)
                    for try await token in try await client.textStream(from: input) {
                        continuation.yield(.token(token))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    mutating func unload() { client = nil }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct LeapBackend: InferenceBackend {
    static let supported: Set<ModelFormat> = [.slm]
    private var client: LeapLLMClient?
    
    mutating func load(_ installed: InstalledModel) async throws {
        let runner = try await Leap.load(url: installed.url)
        let ident = installed.url.deletingPathExtension().lastPathComponent
        client = LeapLLMClient.make(runner: runner, modelIdentifier: ident)
    }
    
    func generate(streaming request: GenerateRequest) -> AsyncThrowingStream<TokenEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let client = client else {
                continuation.finish(throwing: NSError(domain: "Noema", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "LeapBackend client not loaded"]))
                return
            }
            
            Task {
                do {
                    let input = LLMInput.plain(request.prompt)
                    for try await token in try await client.textStream(from: input) {
                        continuation.yield(.token(token))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    mutating func unload() { client = nil }
}

final class BackendRouter {
    private var backend: (any InferenceBackend)?
    func open(model: InstalledModel) async throws -> any InferenceBackend {
        if let current = backend { var c = current; c.unload() }
        if LlamaBackend.supported.contains(model.format) {
            var b = LlamaBackend()
            try await b.load(model)
            backend = b
            return b
        }
        if MLXBackend.supported.contains(model.format) {
            if !DeviceGPUInfo.supportsGPUOffload {
                throw NSError(
                    domain: "Noema",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "MLX models require A13+ GPU on this device. For best performance, use SLM (Leap) models; otherwise use GGUF."]
                )
            }
            var b = MLXBackend()
            try await b.load(model)
            backend = b
            return b
        }
        if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
            if LeapBackend.supported.contains(model.format) {
                var b = LeapBackend()
                try await b.load(model)
                backend = b
                return b
            }
        }
        throw NSError(domain: "Noema", code: -1, userInfo: [NSLocalizedDescriptionKey: "Requested backend unavailable on this build"])
    }
}
