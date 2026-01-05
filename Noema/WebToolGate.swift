// WebToolGate.swift
import Foundation
import CoreGraphics
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

struct WebToolGate {
    // Background-safe gate that avoids MainActor by reading persisted defaults directly.
    static func isAvailable(currentFormat: ModelFormat? = nil) -> Bool {
        let d = UserDefaults.standard
        let enabled = d.object(forKey: "webSearchEnabled") as? Bool ?? true
        let offGrid = d.object(forKey: "offGrid") as? Bool ?? false
        // Keep kill switch in sync even if settings change outside SettingsView
        NetworkKillSwitch.setEnabled(offGrid)
        if offGrid { return false }

        let armed = d.object(forKey: "webSearchArmed") as? Bool ?? false
        let isRemote = d.object(forKey: "currentModelIsRemote") as? Bool ?? false
        // Datasets take precedence: when a dataset is selected or indexing, web search is disabled.
        let selectedDatasetID = d.string(forKey: "selectedDatasetID") ?? ""
        let indexingDatasetID = d.string(forKey: "indexingDatasetIDPersisted") ?? ""
        let datasetActiveOrIndexing = (!selectedDatasetID.isEmpty) || (!indexingDatasetID.isEmpty)
        // Resolve current model format (fallback to persisted if not provided)
        var fmt = currentFormat
        if fmt == nil, let fmtStr = d.string(forKey: "currentModelFormat"), let f = ModelFormat(rawValue: fmtStr) {
            fmt = f
        }

        // Only allow when the loaded model supports function calling (from model card/capability detector)
        // Leap SLM models are intentionally blocked from using web search.
        if let f = fmt {
            if f == .slm { return false }
            if f == .mlx && !isRemote { return false }
        }
        let supportsFunctionCalling = d.object(forKey: "currentModelSupportsFunctionCalling") as? Bool ?? false
        if supportsFunctionCalling == false { return false }

        // Basic availability check (dataset use overrides and disables web search)
        return enabled && armed && !datasetActiveOrIndexing
    }
}

// MARK: - LlamaVisionSession (thin Swift wrapper)

/// A thin, Swift-owning wrapper around the vision-capable llama.cpp C API.
/// - Owns model, context, and optionally an external projector (if the linked llama.cpp exposes that field).
/// - Presents two generation entry points: UIImage+prompt (iOS) and URL+prompt (platform neutral).
/// - On deinit, frees context, projector (if any), then the model in strict reverse order.
final class LlamaVisionSession {
    // Opaque C handles bridged from llama.h
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    // Some llama.cpp builds attach the projector via model params (mparams.mmproj). We still
    // keep a placeholder pointer to follow the requested ownership shape. It remains nil when
    // the projector is merged or attached through model params.
    private var projector: OpaquePointer?

    // Cancellation flag consulted between decode steps
    private var cancelRequested = false

    // Session defaults (can be customized by the app later if desired)
    public var nCtx: Int32 = 4096
    public var nThreads: Int32 = max(1, Int32(ProcessInfo.processInfo.activeProcessorCount - 1))
    public var nGpuLayers: Int32 = 0

    enum VisionError: Error, CustomStringConvertible {
        case modelLoadFailed
        case projectorLoadFailed
        case contextCreateFailed
        case contextMissing
        case visionUnavailable
        case imageInvalid
        case imageEncodeFailed
        case tokenizeFailed
        case decodeFailed

        var description: String {
            switch self {
            case .modelLoadFailed: return "Failed to load GGUF model."
            case .projectorLoadFailed: return "Failed to attach projector (mmproj)."
            case .contextCreateFailed: return "Failed to create llama context."
            case .contextMissing: return "Context is missing or already freed."
            case .visionUnavailable: return "Vision entry points not available in linked llama.cpp."
            case .imageInvalid: return "Invalid image or CGImage conversion failed."
            case .imageEncodeFailed: return "Image encoding into context failed."
            case .tokenizeFailed: return "Tokenization failed."
            case .decodeFailed: return "Decode/evaluate failed."
            }
        }
    }

    // MARK: Init / Deinit

    init(modelURL: URL, projectorURL: URL?) throws {
        // Ensure llama backend lifetime matches Swift object lifetime
        noema_llama_backend_addref()

        // Prepare model params
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = nGpuLayers
        mparams.main_gpu = 0

        if let p = projectorURL?.path {
            // If the linked headers expose a projector field, set it via a small C shim.
            // The shim is a no-op on builds that don’t have mmproj.
            if noema_model_params_set_mmproj(&mparams, p) == false {
                // Keep going; some builds expect merged projector inside the model file.
            }
        }

        // Load model
        guard let mdl = llama_load_model_from_file(modelURL.path, mparams) else {
            noema_llama_backend_release()
            throw VisionError.modelLoadFailed
        }
        self.model = mdl

        // Build context params
        var cparams = llama_context_default_params()
        // Respect model train context when known
        let trainedCtx = llama_n_ctx_train(mdl)
        var effectiveCtx = Int32(nCtx)
        if trainedCtx > 0 && effectiveCtx > trainedCtx { effectiveCtx = trainedCtx }
        // Handle potential unsigned fields in Swift bridge
        // Casts are no-ops if the underlying fields are signed.
        cparams.n_ctx = (try? castNumeric(effectiveCtx, to: cparams.n_ctx)) ?? cparams.n_ctx
        cparams.n_threads = (try? castNumeric(nThreads, to: cparams.n_threads)) ?? cparams.n_threads
        cparams.n_threads_batch = (try? castNumeric(nThreads, to: cparams.n_threads_batch)) ?? cparams.n_threads_batch
        cparams.n_batch = (try? castNumeric(512, to: cparams.n_batch)) ?? cparams.n_batch
        cparams.n_ubatch = (try? castNumeric(512, to: cparams.n_ubatch)) ?? cparams.n_ubatch
        cparams.n_seq_max = (try? castNumeric(1, to: cparams.n_seq_max)) ?? cparams.n_seq_max

        // Create context
        guard let c = llama_init_from_model(mdl, cparams) else {
            llama_model_free(mdl)
            self.model = nil
            noema_llama_backend_release()
            throw VisionError.contextCreateFailed
        }
        self.ctx = c
        llama_set_n_threads(c, Int32(truncatingIfNeeded: cparams.n_threads), Int32(truncatingIfNeeded: cparams.n_threads))
    }

    deinit {
        if let c = ctx { llama_free(c); ctx = nil }
        if let p = projector {
            // If a separate projector handle was acquired via future helpers, free here.
            // Current builds attach projectors via model params; nothing to do.
            _ = p
        }
        if let m = model { llama_model_free(m); model = nil }
        noema_llama_backend_release()
    }

    // MARK: Public API

    #if canImport(UIKit)
    func generate(prompt: String, image: UIImage, maxTokens: Int) throws -> String {
        guard let cgimg = image.cgImage else { throw VisionError.imageInvalid }
        let rgba = try RGBA.from(cgimg: cgimg)
        return try generateInternal(prompt: prompt, pixels: rgba.data, width: rgba.width, height: rgba.height, stride: rgba.stride, maxTokens: maxTokens)
    }
    #endif

    func generate(prompt: String, imageURL: URL, maxTokens: Int) throws -> String {
        // Prefer a direct image loader if present in the runtime; otherwise decode to RGBA8 via CoreGraphics
        if NoemaVisionRuntime.symbolsAvailable == false {
            // Fallback to manual decode path; if the build truly lacks vision encode hooks we will throw later
            let decoded = try ImageDecode.decodeRGBA8(at: imageURL)
            return try generateInternal(prompt: prompt, pixels: decoded.data, width: decoded.width, height: decoded.height, stride: decoded.stride, maxTokens: maxTokens)
        }
        // When vision symbols exist, still decode to RGBA8 for a consistent ingest shape.
        let decoded = try ImageDecode.decodeRGBA8(at: imageURL)
        return try generateInternal(prompt: prompt, pixels: decoded.data, width: decoded.width, height: decoded.height, stride: decoded.stride, maxTokens: maxTokens)
    }

    func cancel() { cancelRequested = true }

    // MARK: Core impl

    private func generateInternal(prompt: String, pixels: Data, width: Int, height: Int, stride: Int, maxTokens: Int) throws -> String {
        guard let c = ctx, let m = model else { throw VisionError.contextMissing }

        // Encode image into the context if possible
        if NoemaVisionRuntime.symbolsAvailable == false {
            throw VisionError.visionUnavailable
        }

        let ok = pixels.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return noema_encode_image_rgba8_into_ctx(c, base, Int32(width), Int32(height), Int32(stride))
        }
        if ok == false { throw VisionError.imageEncodeFailed }

        // Compose text with the required image placeholder for LLaVA-style formats
        // Note: The app’s prompt builder will typically inject placeholders already.
        let formatted = "<image>\n" + prompt

        // Tokenize
        var toks = [llama_token](repeating: 0, count: max(1024, formatted.utf8.count * 4 + 16))
        let vocab = llama_model_get_vocab(m)
        let nInput: Int32 = formatted.withCString { cs in
            return toks.withUnsafeMutableBufferPointer { buf in
                llama_tokenize(vocab, cs, Int32(strlen(cs)), buf.baseAddress, Int32(buf.count), true, true)
            }
        }
        if nInput <= 0 { throw VisionError.tokenizeFailed }

        // Evaluate the prompt
        let nBatchAlloc: Int32 = 512
        var batch = llama_batch_init(nBatchAlloc, 0, 1)
        defer { llama_batch_free(batch) }
        llama_set_embeddings(c, false)

        var nCur: Int32 = 0
        while nCur < nInput {
            if cancelRequested { return "" }
            batch.n_tokens = 0
            let nChunk = min(nInput - nCur, nBatchAlloc)
            noema_batch_clear_logits(&batch, Int32(nChunk))
            for i in 0..<nChunk {
                let pos = nCur + i
                let idx32 = Int32(batch.n_tokens)
                noema_batch_set(&batch, idx32, toks[Int(pos)], Int32(pos), Int32(0), i == nChunk - 1)
                batch.n_tokens += 1
            }
            if llama_decode(c, batch) != 0 { throw VisionError.decodeFailed }
            nCur += nChunk
        }

        // Sampler chain: temperature + top-k + penalties + greedy tail
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(chain) }
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(64, 1.1, 0.0, 0.0))
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        llama_sampler_reset(chain)

        var out = ""
        let ctxMax = Int32(llama_n_ctx(c))
        var posMain = max(nInput, Int32(1))
        var generated = 0
        while generated < maxTokens {
            if cancelRequested { break }
            let tok = llama_sampler_sample(chain, c, -1)
            if tok < 0 || tok == llama_vocab_eos(vocab) { break }
            llama_sampler_accept(chain, tok)
            // Append piece to string
            var buf = [CChar](repeating: 0, count: 512)
            let wrote = llama_token_to_piece(vocab, tok, &buf, Int32(buf.count), 0, false)
            if wrote > 0 { out += String(cString: buf) }
            // Feed back token
            if posMain >= ctxMax - 1 { break }
            batch.n_tokens = 0
            noema_batch_clear_logits(&batch, Int32(1))
            noema_batch_set(&batch, Int32(0), tok, Int32(posMain), Int32(0), true)
            batch.n_tokens = 1
            if llama_decode(c, batch) != 0 { break }
            posMain += 1
            generated += 1
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Vision runtime probes and shims

private enum NoemaVisionRuntime {
    // Prefer the runtime probe that Noema already ships via LlamaRunner
    static var symbolsAvailable: Bool {
        return LlamaRunner.runtimeHasVisionSymbols()
    }
}

// MARK: - RGBA8 conversion helpers

private enum RGBA {
    static func from(cgimg: CGImage) throws -> (data: Data, width: Int, height: Int, stride: Int) {
        let width = cgimg.width
        let height = cgimg.height
        let bytesPerPixel = 4
        let stride = width * bytesPerPixel
        var data = Data(count: stride * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        // Non-premultiplied RGBA8 with alpha last in sRGB space
        let alphaInfo = CGImageAlphaInfo.last
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: alphaInfo.rawValue))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        var ok = false
        data.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                if let ctx = CGContext(data: base,
                                       width: width,
                                       height: height,
                                       bitsPerComponent: 8,
                                       bytesPerRow: stride,
                                       space: colorSpace,
                                       bitmapInfo: bitmapInfo.rawValue) {
                    ctx.interpolationQuality = .high
                    ctx.draw(cgimg, in: rect)
                    ok = true
                }
            }
        }
        if ok == false { throw LlamaVisionSession.VisionError.imageInvalid }
        return (data, width, height, stride)
    }
}

private enum ImageDecode {
    static func decodeRGBA8(at url: URL) throws -> (data: Data, width: Int, height: Int, stride: Int) {
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: true,
                                     kCGImageSourceShouldAllowFloat: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw LlamaVisionSession.VisionError.imageInvalid
        }
        return try RGBA.from(cgimg: cg)
    }
}

// MARK: - C helpers bridged from Objective-C++

/// Attach an external projector into llama_model_params when supported by the linked headers.
/// Returns false when the field does not exist in this build.
@_silgen_name("noema_model_params_set_mmproj")
private func noema_model_params_set_mmproj(_ params: UnsafeMutablePointer<llama_model_params>!, _ path: UnsafePointer<CChar>!) -> Bool

/// Encode a single RGBA8 image into the current llama context using whatever vision path
/// the linked llama.cpp exposes (LLaVA/MTMD). Returns true on success.
@_silgen_name("noema_encode_image_rgba8_into_ctx")
private func noema_encode_image_rgba8_into_ctx(_ ctx: OpaquePointer!, _ rgba: UnsafeRawPointer!, _ width: Int32, _ height: Int32, _ stride: Int32) -> Bool

// MARK: - Numeric casting helper to tolerate signed/unsigned field diffs across headers
@inline(__always)
private func castNumeric<T: BinaryInteger, U: BinaryInteger>(_ value: T, to _: U) throws -> U {
    if let u = U(exactly: value) { return u }
    // Clamp rather than crash on extreme values. Context fields are within 32-bit ranges.
    if value < 0 { return U(0) }
    return U(truncatingIfNeeded: value)
}
