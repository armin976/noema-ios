// ModelDownloadManager.swift
import Foundation
import CryptoKit

enum DownloadEvent {
    case started(Int64?)
    case progress(Double, Int64, Int64, Double)
    case verifying
    case finished(InstalledModel)
    case failed(Error)
    case cancelled
    case paused(Double)
    case networkError(Error, Double) // Network error with current progress
}

actor ModelDownloadManager {
    private var active: [String: Task<Void, Never>] = [:]
    private var dataTasks: [String: URLSessionDataTask] = [:]
    private var verbose: Bool { UserDefaults.standard.bool(forKey: "verboseLogging") }

    private func registerDataTask(_ task: URLSessionDataTask, for key: String) {
        dataTasks[key] = task
    }

    private func clearDataTask(for key: String, cancel: Bool = false) {
        if cancel { dataTasks[key]?.cancel() }
        dataTasks[key] = nil
    }

    // MARK: - Public controls
    func pause(modelID: String, quantLabel: String) {
        let key = "\(modelID)-\(quantLabel)"
        // Cancel the underlying data task only; keep temp file for resume
        clearDataTask(for: key, cancel: true)
    }

    func download(_ quant: QuantInfo, for modelID: String) -> AsyncStream<DownloadEvent> {
        AsyncStream { continuation in
            let key = "\(modelID)-\(quant.label)"
            if let existing = active[key] {
                existing.cancel()
            }

            let task = Task {
                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("LocalLLMModels", isDirectory: true)
                    .appendingPathComponent(modelID, isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                // Persist the canonical repo id for later recovery of assets
                let repoFile = dir.appendingPathComponent("repo.txt")
                try? modelID.data(using: .utf8)?.write(to: repoFile)
                let tmp = dir.appendingPathComponent("\(quant.label).download")

                continuation.yield(.started(quant.sizeBytes))

                final class Delegate: NSObject, URLSessionDataDelegate {
                    let handle: FileHandle
                    var hasher: SHA256?
                    var expected: Int64
                    var bytes: Int64 = 0
                    var lastBytes: Int64
                    var lastTime: Date
                    var lastProgress: Double
                    let startOffset: Int64
                    let progress: @Sendable (Double, Int64, Double) -> Void

                    init(handle: FileHandle, expected: Int64, sha: Bool, start: Date, startOffset: Int64, progress: @escaping @Sendable (Double, Int64, Double) -> Void) {
                        self.handle = handle
                        self.expected = expected
                        self.startOffset = startOffset
                        self.progress = progress
                        self.lastTime = start
                        self.lastBytes = 0
                        self.lastProgress = expected > 0 ? Double(startOffset) / Double(expected) : 0
                        if sha { self.hasher = SHA256() }
                    }

                    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                        if expected <= 0 { expected = response.expectedContentLength }
                        completionHandler(.allow)
                    }

                    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                        try? handle.write(contentsOf: data)
                        hasher?.update(data: data)
                        bytes += Int64(data.count)

                        let now = Date()
                        let total = startOffset + bytes
                        let prog = expected > 0 ? Double(total) / Double(expected) : 0
                        if prog - lastProgress >= 0.01 || now.timeIntervalSince(lastTime) >= 0.3 {
                            let speed = Double(bytes - lastBytes) / now.timeIntervalSince(lastTime)
                            lastBytes = bytes
                            lastTime = now
                            lastProgress = prog
                            progress(prog, total, speed)
                        }
                    }

                    private var cont: CheckedContinuation<Void, Error>?
                    func wait() async throws {
                        try await withCheckedThrowingContinuation { self.cont = $0 }
                    }
                    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                        try? handle.close()
                        if let e = error { cont?.resume(throwing: e) } else { cont?.resume() }
                    }

                    func finalizeHash() -> String? {
                        guard let h = hasher else { return nil }
                        return h.finalize().map { String(format: "%02x", $0) }.joined()
                    }
                }

                do {
                    let start = Date()
                    // Open temp file for append (resume if exists)
                    var startOffset: Int64 = 0
                    if FileManager.default.fileExists(atPath: tmp.path) {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path), let sz = attrs[.size] as? Int64 {
                            startOffset = sz
                        }
                    } else {
                        FileManager.default.createFile(atPath: tmp.path, contents: nil)
                    }
                    let handle = try FileHandle(forWritingTo: tmp)
                    try? handle.seekToEnd()
                    if quant.sizeBytes > 0 && startOffset > 0 {
                        continuation.yield(.progress(Double(startOffset) / Double(quant.sizeBytes), startOffset, quant.sizeBytes, 0))
                    }
                    let delegate = Delegate(handle: handle, expected: quant.sizeBytes, sha: quant.sha256 != nil, start: start, startOffset: startOffset) { p, b, s in
                        continuation.yield(.progress(p, b, quant.sizeBytes, s))
                    }

                    let config = URLSessionConfiguration.default
                    config.waitsForConnectivity = true
                    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
                    NetworkKillSwitch.track(session: session)
                    var request = URLRequest(url: quant.downloadURL)
                    request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                    if startOffset > 0 {
                        request.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
                    }
                    if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    if verbose { print("DOWNLOAD_START \(Date().timeIntervalSince1970)") }
                    let dataTask = session.dataTask(with: request)
                    await registerDataTask(dataTask, for: key)
                    dataTask.resume()
                    try await delegate.wait()
                    await clearDataTask(for: key)
                    if verbose { print("DOWNLOAD_END \(Date().timeIntervalSince1970)") }

                    continuation.yield(.progress(1, startOffset + delegate.bytes, delegate.expected, 0))
                    continuation.yield(.verifying)

                    // Validate GGUF magic to avoid saving HTML or Git LFS pointers as model files
                    if quant.format == .gguf {
                        do {
                            // If the server served HTML (e.g., rate limit page), bail out
                            // Basic sniff: ensure file begins with GGUF magic
                            let readHandle = try FileHandle(forReadingFrom: tmp)
                            defer { try? readHandle.close() }
                            let magic = try readHandle.read(upToCount: 4) ?? Data()
                            if magic != Data("GGUF".utf8) {
                                throw URLError(.cannotParseResponse)
                            }
                        } catch {
                            throw URLError(.cannotParseResponse)
                        }
                    }

                    if let sha = quant.sha256 {
                        if delegate.finalizeHash() != sha { throw URLError(.cannotParseResponse) }
                    }

                    let final = dir.appendingPathComponent(quant.downloadURL.lastPathComponent)
                    try? FileManager.default.removeItem(at: final)
                    try FileManager.default.moveItem(at: tmp, to: final)
                    // Persist artifact pointers for later recovery
                    do {
                        let artifactsURL = dir.appendingPathComponent("artifacts.json")
                        var obj: [String: Any] = [:]
                        if let data = try? Data(contentsOf: artifactsURL),
                           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            obj = parsed
                        }
                        // Always update weights pointer; preserve existing projector info
                        obj["weights"] = final.lastPathComponent
                        if obj["mmproj"] == nil { obj["mmproj"] = NSNull() }
                        let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
                        try? out.write(to: artifactsURL)
                    } catch {}
                    // Fetch and cache hub metadata (pipeline_tag, gguf.chat_template, etc.)
                    if let meta = await HuggingFaceMetadataCache.fetchAndCache(repoId: modelID, token: UserDefaults.standard.string(forKey: "huggingFaceToken")) {
                        HuggingFaceMetadataCache.saveToModelDir(meta: meta, modelID: modelID, format: quant.format)
                    }
                    if let cfgURL = quant.configURL {
                        do {
                            var req = URLRequest(url: cfgURL)
                            req.setValue("application/json", forHTTPHeaderField: "Accept")
                            if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                            }
                            if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                            NetworkKillSwitch.track(session: URLSession.shared)
                            let (data, resp) = try await URLSession.shared.data(for: req)
                            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                                // Basic JSON validation to avoid saving HTML error pages
                                if (try? JSONSerialization.jsonObject(with: data)) != nil {
                                    let dest = dir.appendingPathComponent("config.json")
                                    try? data.write(to: dest)
                                }
                            }
                        } catch {
                            // ignore config download failures
                        }
                    }

                    // Ensure MLX tokenizer assets exist alongside weights so the client can load.
                    if quant.format == .mlx {
                        // MLX quants may come from a repo different from the modelID (e.g. curated mirrors).
                        // Resolve the actual Hugging Face repo from the quant URL so we fetch tokenizers
                        // and sidecar files from the correct location.
                        let repoID = huggingFaceRepoID(from: quant.downloadURL) ?? modelID
                        let tokenizerDest = dir.appendingPathComponent("tokenizer.json")
                        if !FileManager.default.fileExists(atPath: tokenizerDest.path) {
                            // Prefer resolve endpoint (works with LFS), then fall back to raw
                            do {
                                let resolveURL = URL(string: "https://huggingface.co/\(repoID)/resolve/main/tokenizer.json?download=1")!
                                var req = URLRequest(url: resolveURL)
                                req.setValue("application/json", forHTTPHeaderField: "Accept")
                                if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                }
                                if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                NetworkKillSwitch.track(session: URLSession.shared)
                                let (data, resp) = try await URLSession.shared.data(for: req)
                                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 0 {
                                    try? data.write(to: tokenizerDest)
                                }
                            } catch {
                                // try raw as fallback
                                do {
                                    let rawURL = URL(string: "https://huggingface.co/\(repoID)/raw/main/tokenizer.json")!
                                    var req = URLRequest(url: rawURL)
                                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                                    if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                    }
                                    if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                    NetworkKillSwitch.track(session: URLSession.shared)
                                    let (data, resp) = try await URLSession.shared.data(for: req)
                                    if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 0 {
                                        try? data.write(to: tokenizerDest)
                                    }
                                } catch {
                                    // Some repos may use alternative tokenizers (e.g. tokenizer.model).
                                    // We ignore failures here; the loader will surface any remaining issues.
                                }
                            }
                        }
                        // Fallback: sentencepiece model
                        if !FileManager.default.fileExists(atPath: tokenizerDest.path) {
                            let spmCandidates = ["tokenizer.model", "spiece.model", "sentencepiece.bpe.model"]
                            for name in spmCandidates {
                                let dest = dir.appendingPathComponent(name)
                                if FileManager.default.fileExists(atPath: dest.path) { break }
                                // Try resolve first, then raw
                                do {
                                    let rURL = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(name)?download=1")!
                                    var req = URLRequest(url: rURL)
                                    req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                                    if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                    }
                                    if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                    NetworkKillSwitch.track(session: URLSession.shared)
                                    let (data, resp) = try await URLSession.shared.data(for: req)
                                    if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 0 {
                                        try? data.write(to: dest)
                                        break
                                    }
                                } catch {}
                                do {
                                    let url = URL(string: "https://huggingface.co/\(repoID)/raw/main/\(name)")!
                                    var req = URLRequest(url: url)
                                    req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                                    if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                    }
                                    if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                    NetworkKillSwitch.track(session: URLSession.shared)
                                    let (data, resp) = try await URLSession.shared.data(for: req)
                                    if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 0 {
                                        try? data.write(to: dest)
                                        break
                                    }
                                } catch {
                                    // try next candidate
                                }
                            }
                        }

                        // Best-effort: fetch common tokenizer side files if present
                        for side in ["tokenizer_config.json", "special_tokens_map.json", "vocab.txt", "merges.txt"] {
                            let dest = dir.appendingPathComponent(side)
                            if FileManager.default.fileExists(atPath: dest.path) { continue }
                            // Prefer resolve first (handles LFS), then raw
                            do {
                                let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(side)?download=1")!
                                var req = URLRequest(url: url)
                                if side.hasSuffix(".json") {
                                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                                } else {
                                    req.setValue("text/plain", forHTTPHeaderField: "Accept")
                                }
                                if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                }
                                if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                NetworkKillSwitch.track(session: URLSession.shared)
                                let (data, resp) = try await URLSession.shared.data(for: req)
                                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                                    try? data.write(to: dest)
                                    continue
                                }
                            } catch {}
                            do {
                                let url = URL(string: "https://huggingface.co/\(repoID)/raw/main/\(side)")!
                                var req = URLRequest(url: url)
                                if side.hasSuffix(".json") {
                                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                                } else {
                                    req.setValue("text/plain", forHTTPHeaderField: "Accept")
                                }
                                if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                }
                                if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                NetworkKillSwitch.track(session: URLSession.shared)
                                let (data, resp) = try await URLSession.shared.data(for: req)
                                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                                    try? data.write(to: dest)
                                }
                            } catch {
                                // optional; ignore
                            }
                        }

                        // If the repo provides a safetensors index, fetch it and any referenced shards.
                        do {
                            let indexURL = URL(string: "https://huggingface.co/\(repoID)/raw/main/model.safetensors.index.json")!
                            var req = URLRequest(url: indexURL)
                            req.setValue("application/json", forHTTPHeaderField: "Accept")
                            if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                            }
                            if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                            NetworkKillSwitch.track(session: URLSession.shared)
                            let (data, resp) = try await URLSession.shared.data(for: req)
                            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                                // Persist the index file
                                let idxDest = dir.appendingPathComponent("model.safetensors.index.json")
                                try? data.write(to: idxDest)
                                // Parse shard list from weight_map values
                                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let weightMap = obj["weight_map"] as? [String: String] {
                                    let shardNames = Array(Set(weightMap.values))
                                    for name in shardNames {
                                        let shardDest = dir.appendingPathComponent(name)
                                        if FileManager.default.fileExists(atPath: shardDest.path) { continue }
                                        do {
                                            let shardURL = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(name)?download=1")!
                                            var sreq = URLRequest(url: shardURL)
                                            if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                                sreq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                            }
                                            let (tmpShard, _) = try await URLSession.shared.download(for: sreq)
                                            try FileManager.default.moveItem(at: tmpShard, to: shardDest)
                                        } catch {
                                            // Best-effort; if shards fail, the later load will surface an error.
                                        }
                                    }
                                }
                            }
                        } catch {
                            // No index present or failed to fetch; ignore.
                        }

                        // Attempt to fetch common VLM processor/projector configs used by MLX VLM models (e.g., SmolVLM)
                        let vlmSidecars: [String] = [
                            "image_processor.json",
                            "processor_config.json",
                            "preprocessor_config.json",
                            "vision_config.json",
                            "open_clip_config.json",
                            "siglip_config.json",
                            "projector.json"
                        ]
                        for side in vlmSidecars {
                            let dest = dir.appendingPathComponent(side)
                            if FileManager.default.fileExists(atPath: dest.path) { continue }
                            // Prefer resolve endpoint; fall back to raw
                            do {
                                let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(side)?download=1")!
                                var req = URLRequest(url: url)
                                req.setValue("application/json", forHTTPHeaderField: "Accept")
                                if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                }
                                if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                NetworkKillSwitch.track(session: URLSession.shared)
                                let (data, resp) = try await URLSession.shared.data(for: req)
                                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 0 {
                                    try? data.write(to: dest)
                                    continue
                                }
                            } catch {}
                            do {
                                let raw = URL(string: "https://huggingface.co/\(repoID)/raw/main/\(side)")!
                                var req = URLRequest(url: raw)
                                req.setValue("application/json", forHTTPHeaderField: "Accept")
                                if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                }
                                if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                NetworkKillSwitch.track(session: URLSession.shared)
                                let (data, resp) = try await URLSession.shared.data(for: req)
                                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 0 {
                                    try? data.write(to: dest)
                                }
                            } catch {
                                // optional
                            }
                        }
                    }

                    // Success - file has been downloaded and moved to final location
                    await clearDataTask(for: key, cancel: false)

                    let layers = ModelScanner.layerCount(for: final, format: quant.format)
                    let canonical = InstalledModelsStore.canonicalURL(for: final, format: quant.format)
                    
                    // Detect capabilities: prefer Hub pipeline tag; fallback to local heuristics
                    let token = UserDefaults.standard.string(forKey: "huggingFaceToken")
                    let meta = await HuggingFaceMetadataCache.fetchAndCache(repoId: modelID, token: token)
                    var isVision = meta?.isVision ?? false
                    // Fallback heuristics per format when hub tags are missing/unreliable
                    if !isVision {
                        switch quant.format {
                        case .gguf:
                            isVision = ChatVM.guessLlamaVisionModel(from: final)
                        case .mlx:
                            isVision = MLXBridge.isVLMModel(at: canonical)
                        case .slm:
                            // Use Leap heuristics: prefer quantization slug check; fall back to bundle scan
                            let slug = final.deletingPathExtension().lastPathComponent
                            isVision = LeapCatalogService.isVisionQuantizationSlug(slug) || LeapCatalogService.bundleLikelyVision(at: canonical)
                        case .apple:
                            isVision = false
                        }
                    }
                    // Tool capability: prefer hub/template/token hints; fallback to local scan of installed files
                    var isToolCapable = await ToolCapabilityDetector.isToolCapable(repoId: modelID, token: token)
                    if isToolCapable == false {
                        isToolCapable = ToolCapabilityDetector.isToolCapableLocal(url: canonical, format: quant.format)
                    }
                    
                    let installed = InstalledModel(modelID: modelID, quantLabel: quant.label, url: canonical, format: quant.format, sizeBytes: quant.sizeBytes, lastUsed: nil, installDate: Date(), checksum: quant.sha256, isFavourite: false, totalLayers: layers, isMultimodal: isVision, isToolCapable: isToolCapable)
                    continuation.yield(.finished(installed))
                } catch is CancellationError {
                    // Task cancelled explicitly (full cancel). Remove temp file.
                    try? FileManager.default.removeItem(at: tmp)
                    continuation.yield(.cancelled)
                    await clearDataTask(for: key, cancel: true)
                } catch {
                    // If the underlying dataTask was cancelled (pause), keep temp file and report paused instead of failed.
                    if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled {
                        // Determine current bytes for a progress estimate
                        let currentBytes = (try? FileHandle(forReadingFrom: tmp).seekToEnd()) ?? 0
                        let prog = quant.sizeBytes > 0 ? Double(currentBytes) / Double(quant.sizeBytes) : 0
                        continuation.yield(.paused(prog))
                    } else if self.isNetworkError(error) {
                        // Network errors should be retryable - keep temp file and report as network error
                        let currentBytes = (try? FileHandle(forReadingFrom: tmp).seekToEnd()) ?? 0
                        let prog = quant.sizeBytes > 0 ? Double(currentBytes) / Double(quant.sizeBytes) : 0
                        continuation.yield(.networkError(error, prog))
                    } else {
                        continuation.yield(.failed(error))
                    }
                    await clearDataTask(for: key, cancel: true)
                }
                continuation.finish()
            }

            active[key] = task
            continuation.onTermination = { [self] _ in
                Task { await self.cancel(modelID: modelID, quantLabel: quant.label) }
            }
        }
    }

    func cancel(modelID: String, quantLabel: String) {
        let key = "\(modelID)-\(quantLabel)"
        active[key]?.cancel()
        active[key] = nil
        clearDataTask(for: key, cancel: true)
    }
    
    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Network-related errors that should be retryable
        let networkErrorCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorCannotFindHost,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed
        ]
        
        if nsError.domain == NSURLErrorDomain && networkErrorCodes.contains(nsError.code) {
            return true
        }
        
        // HTTP 5xx server errors should also be retryable
        if let httpError = error as? URLError,
           let response = httpError.userInfo["NSHTTPURLResponse"] as? HTTPURLResponse {
            return response.statusCode >= 500
        }
        
        return false
    }

    // Extract the owner/repo path from a Hugging Face URL.
    private func huggingFaceRepoID(from url: URL) -> String? {
        guard let host = url.host, host.contains("huggingface.co") else { return nil }
        var parts = url.path.split(separator: "/").filter { !$0.isEmpty }.map(String.init)
        // Skip common API/CDN prefixes like `/repos` or `/api/models`
        let prefixes: Set<String> = ["repos", "api", "models"]
        while parts.count > 2, let first = parts.first, prefixes.contains(first) {
            parts.removeFirst()
        }
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        let repo = parts[1]
        guard !owner.isEmpty && !repo.isEmpty else { return nil }
        return "\(owner)/\(repo)"
    }
}
