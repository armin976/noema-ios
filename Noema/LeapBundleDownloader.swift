// LeapBundleDownloader.swift
import Foundation
import CryptoKit

/// Downloader for Leap SLM bundles using the Hugging Face models API.
///
/// It discovers bundle filenames via `https://huggingface.co/api/models/LiquidAI/LeapBundles`
/// and downloads using the `resolve/main/<filename>?download=1` endpoint with
/// support for resume, Hugging Face tokens, and progress updates.
final class LeapBundleDownloader: NSObject, @unchecked Sendable {

    enum State: Equatable {
        case notInstalled
        case downloading(Double)
        case installed(URL)
        case failed(String)
    }

    static let shared = LeapBundleDownloader()

    private let queue = DispatchQueue(label: "noema.leap.downloader")
    private var continuations: [String: AsyncStream<DownloadEvent>.Continuation] = [:] // keyed by quantization slug
    private var dataTasks: [String: URLSessionDataTask] = [:] // keyed by quantization slug
    private var progressMap: [String: Double] = [:] // keyed by quantization slug

    private override init() { super.init() }

    /// Async status using local file presence or in-memory progress.
    func statusAsync(for entry: LeapCatalogEntry) async -> State {
        let slug = entry.slug
        // Installed path: Application Support/Models/<slug>.bundle
        let base = InstalledModelsStore.baseDir(for: .slm, modelID: slug)
        let finalURL = base.appendingPathComponent(slug + ".bundle")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: finalURL.path, isDirectory: &isDir), !isDir.boolValue {
            return .installed(finalURL)
        }
        // If there is an active download, report progress
        var currentProgress: Double?
        queue.sync { currentProgress = progressMap[slug] }
        if let p = currentProgress { return .downloading(p) }
        // If there's a temp file, estimate progress from size/expected
        let tmp = base.appendingPathComponent(slug + ".bundle.download")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path),
           let sz = attrs[.size] as? Int64, entry.sizeBytes > 0 {
            let p = max(0, min(1, Double(sz) / Double(entry.sizeBytes)))
            return .downloading(p)
        }
        return .notInstalled
    }

    /// Legacy sync status kept for compatibility; returns .notInstalled.
    func status(for entry: LeapCatalogEntry) -> State { .notInstalled }

    /// Cancel a specific active download.
    func cancel(slug: String) {
        queue.sync {
            dataTasks[slug]?.cancel()
            dataTasks[slug] = nil
            if let cont = continuations.removeValue(forKey: slug) {
                cont.yield(.cancelled)
                cont.finish()
            }
            progressMap.removeValue(forKey: slug)
        }
    }

    /// Cancel all active downloads.
    func cancelAll() {
        queue.sync {
            for (_, task) in dataTasks { task.cancel() }
            dataTasks.removeAll()
            for (_, cont) in continuations { cont.yield(.cancelled); cont.finish() }
            continuations.removeAll()
            progressMap.removeAll()
        }
    }

    /// Download a Leap SLM bundle via Hugging Face API and emit DownloadEvent updates.
    func download(_ entry: LeapCatalogEntry) -> AsyncStream<DownloadEvent> {
        // Use the modern makeStream API to avoid type inference issues in closure-based initializers.
        let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))

        let slug = entry.slug

        // Store continuation for external cancellation to emit .cancelled
        queue.sync { continuations[slug] = continuation }
        // Resolve and kick off download in a lightweight task
        Task { [weak self] in
            guard let self else { return }

            // Discover filename and remote metadata from HF API
            struct Meta: Decodable { struct Sibling: Decodable { let rfilename: String; let size: Int?; let lfs: LFS?; struct LFS: Decodable { let sha256: String?; let size: Int? } }; let siblings: [Sibling]? }
            func fetchSibling(for slug: String, token: String?) async throws -> (name: String, size: Int64, sha256: String?) {
                var comps = URLComponents(string: "https://huggingface.co/api/models/LiquidAI/LeapBundles")!
                comps.queryItems = [URLQueryItem(name: "full", value: "1")]
                var request = URLRequest(url: comps.url!)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                if let t = token, !t.isEmpty { request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
                let (data, resp) = try await URLSession.shared.data(for: request)
                if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { throw URLError(.badServerResponse) }
                let meta = try JSONDecoder().decode(Meta.self, from: data)
                let siblings = meta.siblings ?? []
                // Prefer exact match: <slug>.bundle
                let target = slug + ".bundle"
                if let exact = siblings.first(where: { $0.rfilename == target }) {
                    let size = Int64(exact.lfs?.size ?? exact.size ?? 0)
                    return (target, size, exact.lfs?.sha256)
                }
                // Fallback: first .bundle file
                if let any = siblings.first(where: { $0.rfilename.lowercased().hasSuffix(".bundle") }) {
                    let size = Int64(any.lfs?.size ?? any.size ?? 0)
                    return (any.rfilename, size, any.lfs?.sha256)
                }
                throw URLError(.fileDoesNotExist)
            }

            let token = UserDefaults.standard.string(forKey: "huggingFaceToken")
            let base = InstalledModelsStore.baseDir(for: .slm, modelID: slug)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let finalURL = base.appendingPathComponent(slug + ".bundle")
            let tmpURL = base.appendingPathComponent(slug + ".bundle.download")

            // If already installed, finish immediately
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: finalURL.path, isDirectory: &isDir), !isDir.boolValue {
                let installed = InstalledModel(
                    modelID: slug,
                    quantLabel: "",
                    url: finalURL,
                    format: .slm,
                    sizeBytes: entry.sizeBytes,
                    lastUsed: nil,
                    installDate: Date(),
                    checksum: entry.sha256,
                    isFavourite: false,
                    totalLayers: 0,
                    isMultimodal: LeapCatalogService.isVisionQuantizationSlug(slug),
                    isToolCapable: false
                )
                continuation.yield(.finished(installed))
                continuation.finish()
                queue.sync { continuations.removeValue(forKey: slug); progressMap.removeValue(forKey: slug) }
                return
            }

            // Start download
            continuation.yield(.started(entry.sizeBytes > 0 ? entry.sizeBytes : nil))

            // Prepare temp file (resume if exists)
            var startOffset: Int64 = 0
            if FileManager.default.fileExists(atPath: tmpURL.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: tmpURL.path), let sz = attrs[.size] as? Int64 {
                    startOffset = sz
                }
            } else {
                FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
            }

            // Lookup remote bundle metadata
            let sibling: (name: String, size: Int64, sha256: String?)
            do {
                sibling = try await fetchSibling(for: slug, token: token)
            } catch {
                continuation.yield(.failed(error))
                continuation.finish()
                queue.sync { continuations.removeValue(forKey: slug); progressMap.removeValue(forKey: slug) }
                return
            }

            let expectedBytes: Int64 = sibling.size > 0 ? sibling.size : (entry.sizeBytes > 0 ? entry.sizeBytes : 0)
            let resolveURL = URL(string: "https://huggingface.co/LiquidAI/LeapBundles/resolve/main/\(sibling.name)?download=1")!

            final class Delegate: NSObject, URLSessionDataDelegate {
                let handle: FileHandle
                var hasher: SHA256?
                var expected: Int64
                var bytes: Int64 = 0
                var lastBytes: Int64
                var lastTime: Date
                var lastProgress: Double = 0
                let report: @Sendable (Double, Int64, Double) -> Void

                init(handle: FileHandle, expected: Int64, sha: Bool, start: Date, report: @escaping @Sendable (Double, Int64, Double) -> Void) {
                    self.handle = handle
                    self.expected = expected
                    self.report = report
                    self.lastTime = start
                    self.lastBytes = 0
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
                    let prog = expected > 0 ? Double(bytes) / Double(expected) : 0
                    if prog - lastProgress >= 0.01 || now.timeIntervalSince(lastTime) >= 0.3 {
                        let speed = Double(bytes - lastBytes) / now.timeIntervalSince(lastTime)
                        lastBytes = bytes
                        lastTime = now
                        lastProgress = prog
                        report(prog, bytes, speed)
                    }
                }

                private var cont: CheckedContinuation<Void, Error>?
                func wait() async throws { try await withCheckedThrowingContinuation { self.cont = $0 } }
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
                if !FileManager.default.fileExists(atPath: tmpURL.path) { FileManager.default.createFile(atPath: tmpURL.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: tmpURL)
                try? handle.seekToEnd()
                let delegate = Delegate(handle: handle, expected: expectedBytes, sha: (entry.sha256 ?? sibling.sha256) != nil, start: start) { p, b, s in
                    self.queue.sync { self.progressMap[slug] = p }
                    continuation.yield(.progress(p, b, expectedBytes, s))
                }

                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                NetworkKillSwitch.track(session: session)
                var request = URLRequest(url: resolveURL)
                request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                if startOffset > 0 { request.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range") }
                if let t = token, !t.isEmpty { request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }

                let dataTask = session.dataTask(with: request)
                queue.sync { dataTasks[slug] = dataTask }
                dataTask.resume()
                try await delegate.wait()
                queue.sync { dataTasks[slug] = nil }

                continuation.yield(.progress(1, delegate.bytes, delegate.expected, 0))
                continuation.yield(.verifying)

                // Verify checksum if available
                if let sha = (entry.sha256 ?? sibling.sha256), let computed = delegate.finalizeHash(), sha.lowercased() != computed.lowercased() {
                    throw URLError(.cannotParseResponse)
                }

                try? FileManager.default.removeItem(at: finalURL)
                try FileManager.default.moveItem(at: tmpURL, to: finalURL)

                let isVision = LeapCatalogService.isVisionQuantizationSlug(entry.slug)
                let installed = InstalledModel(
                    modelID: entry.slug,
                    quantLabel: "",
                    url: finalURL,
                    format: .slm,
                    sizeBytes: delegate.expected > 0 ? delegate.expected : expectedBytes,
                    lastUsed: nil,
                    installDate: Date(),
                    checksum: entry.sha256 ?? sibling.sha256,
                    isFavourite: false,
                    totalLayers: 0,
                    isMultimodal: isVision,
                    isToolCapable: false
                )
                continuation.yield(.finished(installed))
                continuation.finish()
                queue.sync { continuations.removeValue(forKey: slug); progressMap.removeValue(forKey: slug) }
            } catch {
                continuation.yield(.failed(error))
                continuation.finish()
                queue.sync {
                    continuations.removeValue(forKey: slug)
                    dataTasks[slug]?.cancel()
                    dataTasks[slug] = nil
                    progressMap.removeValue(forKey: slug)
                }
            }
        }

        continuation.onTermination = { [weak self] term in
            guard let self else { return }
            if case .cancelled = term {
                self.cancel(slug: slug)
            }
        }

        return stream
    }

    /// Normalizes SLM bundle URLs that may point to inner files rather than the bundle root
    /// and updates persisted selections when needed. This is a best-effort no-op when paths
    /// are already canonical.
    static func sanitizeBundleIfNeeded(at url: URL) {
        let fixed = url.resolvingSymlinksInPath().standardizedFileURL

        // If the provided URL is inside a "*.bundle" directory, prefer the bundle root.
        func bundleRoot(for url: URL) -> URL? {
            let parent = url.deletingLastPathComponent()
            if parent.pathExtension.lowercased() == "bundle" { return parent }
            return nil
        }

        // Compute preferred target
        let preferred: URL
        if let root = bundleRoot(for: fixed) {
            preferred = root
        } else if fixed.pathExtension.lowercased() == "bundle" {
            preferred = fixed
        } else {
            preferred = fixed
        }

        // If the path changed and the old selection matches defaults, update it.
        if preferred != fixed {
            let defaults = UserDefaults.standard
            if let current = defaults.string(forKey: "defaultModelPath"), !current.isEmpty,
               current == fixed.path {
                defaults.set(preferred.path, forKey: "defaultModelPath")
            }
        }

        // If the preferred is a bundle but exists as a file while a directory with the same
        // name exists, prefer the directory by updating defaults.
        if preferred.pathExtension.lowercased() == "bundle" {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: preferred.path, isDirectory: &isDir)
            if exists && !isDir.boolValue {
                // Check if a directory with the same name already exists (edge case after migrations)
                // Nothing actionable without moving files; keep this as a no-op to avoid data loss.
                return
            }
        }
    }
}

