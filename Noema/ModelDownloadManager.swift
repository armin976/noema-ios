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

// MARK: - Safetensors Validation Helpers

/// Checks if a file is a Git LFS pointer instead of actual content.
/// LFS pointers are small text files starting with "version https://git-lfs.github.com/spec/v1"
func isGitLFSPointer(at url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }

    // LFS pointers are typically <200 bytes
    guard let data = try? handle.read(upToCount: 200) else { return false }
    guard let text = String(data: data, encoding: .utf8) else { return false }

    return text.hasPrefix("version https://git-lfs.github.com/spec/v1")
}

/// Validates that a safetensors file has a valid header.
/// Safetensors format: first 8 bytes are header length (u64 little endian), followed by JSON header.
/// Returns true if valid, false if corrupted/incomplete.
func isValidSafetensorsFile(at url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }

    // Read first 8 bytes for header length
    guard let headerLengthData = try? handle.read(upToCount: 8), headerLengthData.count == 8 else {
        return false
    }

    // Parse as little-endian u64
    let headerLength = headerLengthData.withUnsafeBytes { $0.load(as: UInt64.self) }

    // Sanity check: header should be reasonable size (< 100MB)
    if headerLength > 100_000_000 {
        return false
    }

    // Try to read and parse the JSON header
    guard let headerData = try? handle.read(upToCount: Int(headerLength)) else {
        return false
    }

    // Verify it's valid JSON
    guard let _ = try? JSONSerialization.jsonObject(with: headerData) else {
        return false
    }

    return true
}

/// Returns the file size in bytes, or nil if file doesn't exist
func fileSize(at url: URL) -> Int64? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attrs[.size] as? Int64 else {
        return nil
    }
    return size
}

actor ModelDownloadManager {
    private var active: [String: Task<Void, Never>] = [:]
    private var dataTasks: [String: URLSessionDataTask] = [:]
    // Track temp destination per active model so we can pause/cancel background tasks
    private var tmpByKey: [String: URL] = [:]
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
        // Prefer pausing the background task so resume data is preserved
        if let tmp = tmpByKey[key] {
            // Hop to main without making this method async
            Task { @MainActor in BackgroundDownloadManager.shared.pause(destination: tmp) }
        } else {
            // Legacy: cancel any foreground data task
            clearDataTask(for: key, cancel: true)
        }
    }

    func download(_ quant: QuantInfo, for modelID: String) -> AsyncStream<DownloadEvent> {
        AsyncStream { continuation in
            let key = "\(modelID)-\(quant.label)"
            if let existing = active[key] {
                existing.cancel()
            }

            let task = Task {
                let dir = InstalledModelsStore.baseDir(for: quant.format, modelID: modelID)
                let authToken = UserDefaults.standard.string(forKey: "huggingFaceToken")?.trimmingCharacters(in: .whitespacesAndNewlines)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                // Persist the canonical repo id for later recovery of assets
                let repoFile = dir.appendingPathComponent("repo.txt")
                try? modelID.data(using: .utf8)?.write(to: repoFile)
                let tmp = dir.appendingPathComponent("\(quant.label).download")
                self.tmpByKey[key] = tmp

                continuation.yield(.started(quant.sizeBytes))

                // Track progress via an actor to satisfy Sendable rules for the progress handler
                // Throttle instantaneous speed calculation to avoid unrealistically large spikes
                // from very small time deltas between delegate callbacks.
                actor ProgressState {
                    // Always track last observed bytes so snapshot() can report progress immediately
                    private var lastBytes: Int64 = 0
                    private(set) var latestSpeed: Double = 0
                    private let expected: Int64

                    // Throttled speed sampling state
                    private var lastSpeedSampleTime: Date? = nil
                    private var lastSpeedSampleBytes: Int64? = nil
                    private let minSampleInterval: TimeInterval = 0.5

                    init(expected: Int64) { self.expected = expected }

                    // Update with the absolute total bytes written so far.
                    // Returns the latest throttled instantaneous speed (bytes/sec).
                    func updateBytes(_ written: Int64) -> Double {
                        lastBytes = written
                        let now = Date()
                        guard let t0 = lastSpeedSampleTime, let b0 = lastSpeedSampleBytes else {
                            lastSpeedSampleTime = now
                            lastSpeedSampleBytes = written
                            latestSpeed = 0
                            return latestSpeed
                        }
                        let dt = now.timeIntervalSince(t0)
                        // Only refresh speed when enough time has elapsed to get a stable estimate
                        guard dt >= minSampleInterval else { return latestSpeed }
                        let bytesDelta = written - b0
                        let speed = dt > 0 ? Double(bytesDelta) / dt : 0
                        latestSpeed = max(0, speed)
                        lastSpeedSampleTime = now
                        lastSpeedSampleBytes = written
                        return latestSpeed
                    }
                    func estimatedBytes(forProgress p: Double) -> Int64 {
                        if expected > 0 { return Int64(Double(expected) * p) }
                        return lastBytes
                    }
                    func snapshotSpeed() -> Double { latestSpeed }
                    func snapshot() -> Double {
                        guard expected > 0 else { return 0 }
                        return Double(lastBytes) / Double(expected)
                    }
                }
                // Background download → tmp path. We compute speeds locally using expected size.
                let expected = quant.sizeBytes
                let progressState = ProgressState(expected: expected)
                // Track the best-known expected total in a tiny actor to satisfy @Sendable rules
                actor ExpectedState {
                    private let initial: Int64
                    private var runtime: Int64
                    init(initial: Int64) { self.initial = initial; self.runtime = initial }
                    func update(_ v: Int64) { if v > 0 { runtime = v } }
                    func total() -> Int64 { return runtime > 0 ? runtime : initial }
                }
                let expectedState = ExpectedState(initial: expected)
                // Track actual bytes written as reported by URLSession delegate to avoid deriving
                // from fraction (which can be throttled/rounded by the OS)
                actor TransferState {
                    private var written: Int64 = 0
                    private var expected: Int64 = -1
                    func update(w: Int64, e: Int64) { written = w; if e > 0 { expected = e } }
                    func snapshot() -> (Int64, Int64) { (written, expected) }
                }
                let transferState = TransferState()
                do {
                    var req = URLRequest(url: quant.downloadURL)
                    req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                    req.setValue("Noema/1.0 (+https://noema.app)", forHTTPHeaderField: "User-Agent")
                    if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    if verbose { print("DOWNLOAD_START \(Date().timeIntervalSince1970)") }
                    let progressHandler: @Sendable (Double) -> Void = { p in
                        Task {
                            let (w, e) = await transferState.snapshot()
                            let total = (e > 0) ? e : await expectedState.total()
                            let s = await progressState.snapshotSpeed()
                            continuation.yield(.progress(p, w, total, s))
                        }
                    }
                    let _ = try await BackgroundDownloadManager.shared.download(
                        request: req,
                        to: tmp,
                        expectedSize: expected,
                        progress: progressHandler,
                        progressBytes: { written, reportedExpected in
                            if reportedExpected > 0 {
                                Task { await expectedState.update(reportedExpected) }
                            }
                            Task { await transferState.update(w: written, e: reportedExpected) }
                            Task { _ = await progressState.updateBytes(written) }
                        })
                    if verbose { print("DOWNLOAD_END \(Date().timeIntervalSince1970)") }

                    let total = await expectedState.total()
                    continuation.yield(.progress(1, Int64(total), total, 0))
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
                        // Compute sha256 over the completed tmp file
                        if let fh = try? FileHandle(forReadingFrom: tmp) {
                            var hasher = SHA256()
                            while autoreleasepool(invoking: {
                                let chunk = try? fh.read(upToCount: 1_048_576) ?? Data()
                                if let c = chunk, !c.isEmpty { hasher.update(data: c); return true }
                                return false
                            }) {}
                            try? fh.close()
                            let computed = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                            if computed.lowercased() != sha.lowercased() { throw URLError(.cannotParseResponse) }
                        }
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

                    // Best-effort: fetch repo-provided sampling hints (params/params.json) to seed default settings.
                    do {
                        let repoID = huggingFaceRepoID(from: quant.downloadURL) ?? modelID
                        try await downloadParamsFile(repoID: repoID, into: dir, token: authToken)
                    } catch {
                        // optional sidecar; ignore failures
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

                        // Best-effort: fetch chat templates (needed by MLX tokenizer/init)
                        // Many HF repos (e.g., Qwen3-VL) ship chat_template.jinja / chat_template.json separately.
                        // If missing locally, MLX will raise "tokenizer does not have a chat template".
                        for tmpl in ["chat_template.json", "chat_template.jinja"] {
                            let dest = dir.appendingPathComponent(tmpl)
                            if FileManager.default.fileExists(atPath: dest.path) { continue }
                            // Prefer resolve (supports LFS), then raw
                            do {
                                let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(tmpl)?download=1")!
                                var req = URLRequest(url: url)
                                if tmpl.hasSuffix(".json") {
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
                                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 0 {
                                    try? data.write(to: dest)
                                    continue
                                }
                            } catch {}
                            do {
                                let raw = URL(string: "https://huggingface.co/\(repoID)/raw/main/\(tmpl)")!
                                var req = URLRequest(url: raw)
                                if tmpl.hasSuffix(".json") {
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
                                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 0 {
                                    try? data.write(to: dest)
                                }
                            } catch {
                                // optional; ignore
                            }
                        }

                        // Download safetensors model weights
                        // Strategy: Try single model.safetensors first, then fall back to sharded files
                        let singleSafetensorsDest = dir.appendingPathComponent("model.safetensors")
                        var needsShardedDownload = true

                        // First, try downloading the single model.safetensors file
                        if !FileManager.default.fileExists(atPath: singleSafetensorsDest.path) ||
                           isGitLFSPointer(at: singleSafetensorsDest) ||
                           !isValidSafetensorsFile(at: singleSafetensorsDest) {

                            print("[ModelDownloadManager] Attempting to download single model.safetensors...")
                            do {
                                let singleURL = URL(string: "https://huggingface.co/\(repoID)/resolve/main/model.safetensors?download=1")!
                                var sreq = URLRequest(url: singleURL)
                                sreq.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                                if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                    sreq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                }

                                if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                NetworkKillSwitch.track(session: URLSession.shared)

                                let (tmpFile, resp) = try await URLSession.shared.download(for: sreq)

                                if let httpResp = resp as? HTTPURLResponse, (200..<300).contains(httpResp.statusCode) {
                                    // Validate before moving
                                    if isGitLFSPointer(at: tmpFile) {
                                        print("[ModelDownloadManager] Downloaded model.safetensors is LFS pointer - will try sharded")
                                        try? FileManager.default.removeItem(at: tmpFile)
                                    } else if !isValidSafetensorsFile(at: tmpFile) {
                                        let size = fileSize(at: tmpFile) ?? 0
                                        print("[ModelDownloadManager] Downloaded model.safetensors has invalid header (size: \(size)) - will try sharded")
                                        try? FileManager.default.removeItem(at: tmpFile)
                                    } else {
                                        // Valid single file - move to destination
                                        try? FileManager.default.removeItem(at: singleSafetensorsDest) // Remove any invalid existing file
                                        try FileManager.default.moveItem(at: tmpFile, to: singleSafetensorsDest)
                                        let finalSize = fileSize(at: singleSafetensorsDest) ?? 0
                                        print("[ModelDownloadManager] Successfully downloaded model.safetensors (\(finalSize / 1_000_000) MB)")
                                        needsShardedDownload = false
                                    }
                                } else if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 404 {
                                    print("[ModelDownloadManager] model.safetensors not found (404) - will try sharded files")
                                    try? FileManager.default.removeItem(at: tmpFile)
                                } else {
                                    print("[ModelDownloadManager] Failed to download model.safetensors - will try sharded")
                                    try? FileManager.default.removeItem(at: tmpFile)
                                }
                            } catch {
                                print("[ModelDownloadManager] Error downloading model.safetensors: \(error) - will try sharded")
                            }
                        } else {
                            print("[ModelDownloadManager] Valid model.safetensors already exists - skipping download")
                            needsShardedDownload = false
                        }

                        // If single file download failed/not available, try sharded download via index
                        if needsShardedDownload {
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
                                        let shardNames = Array(Set(weightMap.values)).sorted()
                                        print("[ModelDownloadManager] Found \(shardNames.count) safetensors shards in index")

                                        var anyShardFailed = false
                                        for name in shardNames {
                                            let shardDest = dir.appendingPathComponent(name)

                                            // Check if file exists and is valid
                                            if FileManager.default.fileExists(atPath: shardDest.path) {
                                                if isGitLFSPointer(at: shardDest) {
                                                    print("[ModelDownloadManager] \(name) is LFS pointer - re-downloading")
                                                    try? FileManager.default.removeItem(at: shardDest)
                                                } else if !isValidSafetensorsFile(at: shardDest) {
                                                    let size = fileSize(at: shardDest) ?? 0
                                                    print("[ModelDownloadManager] \(name) invalid (size: \(size)) - re-downloading")
                                                    try? FileManager.default.removeItem(at: shardDest)
                                                } else {
                                                    print("[ModelDownloadManager] \(name) already valid - skipping")
                                                    continue
                                                }
                                            }

                                            // Download the shard
                                            print("[ModelDownloadManager] Downloading shard: \(name)")
                                            do {
                                                let shardURL = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(name)?download=1")!
                                                var sreq = URLRequest(url: shardURL)
                                                sreq.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                                                if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                                    sreq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                                }

                                                if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                                                NetworkKillSwitch.track(session: URLSession.shared)

                                                let (tmpShard, shardResp) = try await URLSession.shared.download(for: sreq)

                                                if let httpResp = shardResp as? HTTPURLResponse {
                                                    guard (200..<300).contains(httpResp.statusCode) else {
                                                        print("[ModelDownloadManager] Shard \(name): HTTP \(httpResp.statusCode)")
                                                        anyShardFailed = true
                                                        try? FileManager.default.removeItem(at: tmpShard)
                                                        continue
                                                    }
                                                }

                                                // Validate downloaded file
                                                if isGitLFSPointer(at: tmpShard) {
                                                    print("[ModelDownloadManager] ERROR: \(name) is LFS pointer")
                                                    try? FileManager.default.removeItem(at: tmpShard)
                                                    anyShardFailed = true
                                                    continue
                                                }

                                                if !isValidSafetensorsFile(at: tmpShard) {
                                                    let size = fileSize(at: tmpShard) ?? 0
                                                    print("[ModelDownloadManager] ERROR: \(name) invalid header (size: \(size))")
                                                    try? FileManager.default.removeItem(at: tmpShard)
                                                    anyShardFailed = true
                                                    continue
                                                }

                                                try FileManager.default.moveItem(at: tmpShard, to: shardDest)
                                                let finalSize = fileSize(at: shardDest) ?? 0
                                                print("[ModelDownloadManager] Downloaded \(name) (\(finalSize / 1_000_000) MB)")

                                            } catch {
                                                print("[ModelDownloadManager] Failed shard \(name): \(error)")
                                                anyShardFailed = true
                                            }
                                        }

                                        // If any shards failed to download, the index might be stale
                                        // Try the single file as final fallback
                                        if anyShardFailed && !FileManager.default.fileExists(atPath: singleSafetensorsDest.path) {
                                            print("[ModelDownloadManager] Some shards failed - index may be outdated. Model weights may be incomplete.")
                                        }
                                    }
                                }
                            } catch {
                                print("[ModelDownloadManager] No safetensors index or failed to fetch: \(error)")
                            }
                        }

                        // Also fetch the index file if we downloaded a single file (for compatibility)
                        if !needsShardedDownload {
                            let idxDest = dir.appendingPathComponent("model.safetensors.index.json")
                            if !FileManager.default.fileExists(atPath: idxDest.path) {
                                do {
                                    let indexURL = URL(string: "https://huggingface.co/\(repoID)/raw/main/model.safetensors.index.json")!
                                    var req = URLRequest(url: indexURL)
                                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                                    if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
                                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                    }
                                    let (data, resp) = try await URLSession.shared.data(for: req)
                                    if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                                        try? data.write(to: idxDest)
                                        print("[ModelDownloadManager] Also downloaded model.safetensors.index.json")
                                    }
                                } catch {
                                    // Index is optional for single-file models
                                }
                            }
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
                    
                    // Detect capabilities: rely on projector presence for GGUF models
                    let token = UserDefaults.standard.string(forKey: "huggingFaceToken")
                    let authToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
                    var meta = await HuggingFaceMetadataCache.fetchAndCache(repoId: modelID, token: authToken)
                    var isVision = false
                    switch quant.format {
                    case .gguf:
                        if let meta, meta.hasProjectorFile {
                            isVision = true
                        } else {
                            isVision = ProjectorLocator.hasProjectorFile(alongside: canonical)
                            if !isVision, meta == nil {
                                isVision = await VisionModelDetector.isVisionModel(repoId: modelID, token: (authToken?.isEmpty ?? true) ? nil : authToken)
                                if let refreshed = HuggingFaceMetadataCache.cached(repoId: modelID) {
                                    meta = refreshed
                                }
                            }
                        }
                    case .mlx:
                        isVision = MLXBridge.isVLMModel(at: canonical)
                    case .slm:
                        // Use Leap heuristics: prefer quantization slug check; fall back to bundle scan
                        let slug = final.deletingPathExtension().lastPathComponent
                        isVision = LeapCatalogService.isVisionQuantizationSlug(slug) || LeapCatalogService.bundleLikelyVision(at: canonical)
                    case .apple:
                        isVision = false
                    }
                    // Tool capability: prefer hub/template/token hints; fallback to local scan of installed files
                    var isToolCapable = await ToolCapabilityDetector.isToolCapable(repoId: modelID, token: authToken)
                    if isToolCapable == false {
                        isToolCapable = ToolCapabilityDetector.isToolCapableLocal(url: canonical, format: quant.format)
                    }

                    let moeInfo: MoEInfo?
                    switch quant.format {
                    case .gguf, .mlx:
                        let detectedInfo = ModelScanner.moeInfo(for: canonical, format: quant.format)
                        if let detectedInfo {
                            let label = detectedInfo.isMoE ? "MoE" : "Dense"
                            let moeLayers = detectedInfo.moeLayerCount.map(String.init) ?? "n/a"
                            let totalLayers = detectedInfo.totalLayerCount.map(String.init) ?? "n/a"
                            print("[MoEDetect] post-download \(modelID) (\(quant.label)) [\(quant.format.rawValue)] → \(label) experts=\(detectedInfo.expertCount) moeLayers=\(moeLayers) totalLayers=\(totalLayers)")
                            moeInfo = detectedInfo
                        } else {
                            print("[MoEDetect] post-download \(modelID) (\(quant.label)) [\(quant.format.rawValue)] scan failed; defaulting to Dense metadata")
                            moeInfo = .denseFallback
                        }
                        if let info = moeInfo {
                            await MoEDetectionStore.shared.update(info: info, modelID: modelID, quantLabel: quant.label)
                        }
                    case .slm, .apple:
                        moeInfo = nil
                    }

                    let installed = InstalledModel(modelID: modelID,
                                                   quantLabel: quant.label,
                                                   url: canonical,
                                                   format: quant.format,
                                                   sizeBytes: quant.sizeBytes,
                                                   lastUsed: nil,
                                                   installDate: Date(),
                                                   checksum: quant.sha256,
                                                   isFavourite: false,
                                                   totalLayers: layers,
                                                   isMultimodal: isVision,
                                                   isToolCapable: isToolCapable,
                                                   moeInfo: moeInfo)
                    continuation.yield(.finished(installed))
                } catch is CancellationError {
                    // Full cancel
                    try? FileManager.default.removeItem(at: tmp)
                    continuation.yield(.cancelled)
                } catch {
                    let ns = error as NSError
                    if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                        // Pause – estimate using last reported progress
                        let prog = quant.sizeBytes > 0 ? await progressState.snapshot() : 0
                        continuation.yield(.paused(prog))
                    } else if self.isNetworkError(error) {
                        let prog = quant.sizeBytes > 0 ? await progressState.snapshot() : 0
                        continuation.yield(.networkError(error, prog))
                    } else {
                        continuation.yield(.failed(error))
                    }
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
        if let tmp = tmpByKey[key] {
            // Hop to main without making this method async
            Task { @MainActor in BackgroundDownloadManager.shared.cancel(destination: tmp) }
        } else {
            clearDataTask(for: key, cancel: true)
        }
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

    /// Best-effort download of a repo's params / params.json sidecar to seed default sampling settings.
    private func downloadParamsFile(repoID: String, into dir: URL, token: String?) async throws {
        let fm = FileManager.default
        let existing = ["params", "params.json"].first(where: { fm.fileExists(atPath: dir.appendingPathComponent($0).path) })
        if existing != nil { return }
        // Respect offline/kill switch
        if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }

        let candidates = ["params", "params.json"]
        let endpointTemplates = [
            "https://huggingface.co/%@/resolve/main/%@?download=1",
            "https://huggingface.co/%@/raw/main/%@"
        ]

        for name in candidates {
            for tmpl in endpointTemplates {
                guard let url = URL(string: String(format: tmpl, repoID, name)) else { continue }
                var req = URLRequest(url: url)
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                if let token, !token.isEmpty {
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                NetworkKillSwitch.track(session: URLSession.shared)
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else { continue }
                    // Basic sniff to ensure it's JSON
                    guard (try? JSONSerialization.jsonObject(with: data)) != nil else { continue }
                    let dest = dir.appendingPathComponent(name)
                    try data.write(to: dest)
                    return
                } catch {
                    // try next candidate/endpoint
                    continue
                }
            }
        }
    }
}
