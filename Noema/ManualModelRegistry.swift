// ManualModelRegistry.swift
import Foundation

// Concurrency-safe cache for MLX repo details
private actor MlxRepoDetailsCache {
    private var cache: [String: ModelDetails] = [:]

    func get(_ key: String) -> ModelDetails? {
        return cache[key]
    }

    func set(_ key: String, _ value: ModelDetails) {
        cache[key] = value
    }
}

/// Registry providing manually curated model information from various sources.
public final class ManualModelRegistry: ModelRegistry, @unchecked Sendable {
    public struct Entry: Sendable {
        let record: ModelRecord
        let details: ModelDetails
    }

    private let entries: [Entry]

    public init(entries: [Entry] = ManualModelRegistry.defaultEntries) {
        self.entries = entries
    }

    public func curated() async throws -> [ModelRecord] {
        return entries.map { $0.record }
    }


    public func searchStream(query: String, page: Int, includeVisionModels: Bool, visionOnly: Bool) -> AsyncThrowingStream<ModelRecord, Error> {
        // Manual registry doesn't need vision models parameter, but we need to match the protocol
        return .init { continuation in
            continuation.finish()
        }
    }

    public func details(for id: String) async throws -> ModelDetails {
        guard let entry = entries.first(where: { $0.record.id == id }) else {
            throw URLError(.badURL)
        }

        var base = entry.details

        // Prefer pulling quants dynamically like Explore does, then merge curated extras
        let token = UserDefaults.standard.string(forKey: "huggingFaceToken")
        let hf = HuggingFaceRegistry(token: token)

        var quants: [QuantInfo]
        if let det = try? await hf.details(for: base.id) {
            quants = det.quants
        } else {
            quants = base.quants
        }

        // Merge curated extras that point to other Hugging Face repos (e.g., MLX or GGUF mirrors)
        for extra in base.quants {
            guard let repo = huggingFaceRepoID(from: extra.downloadURL) else { continue }
            // Skip if already the same repo; dynamic quants above already covered it
            if repo == base.id { continue }

            if let det = try? await hf.details(for: repo) {
                let candidates = det.quants.filter { $0.format == extra.format }
                var picked: QuantInfo?
                switch extra.format {
                case .mlx:
                    if let bits = extractBitness(from: extra.label) {
                        picked = candidates.first(where: { QuantExtractor.shortLabel(from: $0.label, format: .mlx).lowercased() == "\(bits)bit" }) ?? candidates.first
                    } else {
                        picked = candidates.first
                    }
                case .gguf:
                    let target = QuantExtractor.shortLabel(from: extra.label, format: .gguf).lowercased()
                    picked = candidates.first(where: { QuantExtractor.shortLabel(from: $0.label, format: .gguf).lowercased() == target }) ?? candidates.first
                case .slm, .apple:
                    picked = candidates.first
                }
                if let q = picked {
                    if !quants.contains(where: { $0.downloadURL == q.downloadURL }) {
                        quants.append(q)
                    }
                }
            } else {
                // Fallback: ensure ?download=1 and set config to the repo
                var comps = URLComponents(url: extra.downloadURL, resolvingAgainstBaseURL: false)!
                var q = comps.queryItems ?? []
                if !q.contains(where: { $0.name == "download" }) { q.append(URLQueryItem(name: "download", value: "1")) }
                comps.queryItems = q
                if let newURL = comps.url {
                    let cfg = URL(string: "https://huggingface.co/\(repo)/raw/main/config.json")
                    let candidate = QuantInfo(label: extra.label,
                                              format: extra.format,
                                              sizeBytes: extra.sizeBytes,
                                              downloadURL: newURL,
                                              sha256: extra.sha256,
                                              configURL: extra.configURL ?? cfg)
                    if !quants.contains(where: { $0.downloadURL == candidate.downloadURL }) {
                        quants.append(candidate)
                    }
                }
            }
        }

        // De-duplicate by URL and short label per format to avoid duplicates from merges
        do {
            var unique: [QuantInfo] = []
            var seenURLs: Set<String> = []
            var seenKeys: Set<String> = []
            for q in quants {
                let urlKey = q.downloadURL.absoluteString
                let labelKey = QuantExtractor.shortLabel(from: q.label, format: q.format).lowercased()
                let key = "\(q.format.rawValue):\(labelKey)"
                if seenURLs.contains(urlKey) || seenKeys.contains(key) { continue }
                seenURLs.insert(urlKey)
                seenKeys.insert(key)
                unique.append(q)
            }
            quants = unique
        }

        for i in quants.indices {
            // Resolve MLX curated links only once per repo and only when opening the curated model
            if quants[i].format == .mlx, let host = quants[i].downloadURL.host, host.contains("huggingface.co"), let repo = huggingFaceRepoID(from: quants[i].downloadURL) {
                if let cached = await ManualModelRegistry.mlxRepoDetailsCache.get(repo) {
                    // Prefer MLX quant matching curated label bitness if possible
                    let mlxQuants = cached.quants.filter { $0.format == .mlx }
                    let picked: QuantInfo?
                    if let bits = extractBitness(from: quants[i].label) {
                        picked = mlxQuants.first(where: { QuantExtractor.shortLabel(from: $0.label, format: .mlx).lowercased() == "\(bits)bit" }) ?? mlxQuants.first
                    } else {
                        picked = mlxQuants.first
                    }
                    if let mlxQuant = picked {
                        quants[i] = QuantInfo(label: quants[i].label,
                                              format: .mlx,
                                              sizeBytes: mlxQuant.sizeBytes,
                                              downloadURL: mlxQuant.downloadURL,
                                              sha256: mlxQuant.sha256,
                                              configURL: mlxQuant.configURL ?? URL(string: "https://huggingface.co/\(repo)/raw/main/config.json"))
                    }
                } else {
                    // First time for this curated MLX repo: fetch details and cache
                    let token = UserDefaults.standard.string(forKey: "huggingFaceToken")
                    let hf = HuggingFaceRegistry(token: token)
                    if let det = try? await hf.details(for: repo) {
                        await ManualModelRegistry.mlxRepoDetailsCache.set(repo, det)
                        let mlxQuants = det.quants.filter { $0.format == .mlx }
                        let picked: QuantInfo?
                        if let bits = extractBitness(from: quants[i].label) {
                            picked = mlxQuants.first(where: { QuantExtractor.shortLabel(from: $0.label, format: .mlx).lowercased() == "\(bits)bit" }) ?? mlxQuants.first
                        } else {
                            picked = mlxQuants.first
                        }
                        if let mlxQuant = picked {
                            quants[i] = QuantInfo(label: quants[i].label,
                                                  format: .mlx,
                                                  sizeBytes: mlxQuant.sizeBytes,
                                                  downloadURL: mlxQuant.downloadURL,
                                                  sha256: mlxQuant.sha256,
                                                  configURL: mlxQuant.configURL ?? URL(string: "https://huggingface.co/\(repo)/raw/main/config.json"))
                        }
                    } else {
                        // Fallback: add ?download=1 for size probing and set config to the repo
                        var comps = URLComponents(url: quants[i].downloadURL, resolvingAgainstBaseURL: false)!
                        var q = comps.queryItems ?? []
                        if !q.contains(where: { $0.name == "download" }) { q.append(URLQueryItem(name: "download", value: "1")) }
                        comps.queryItems = q
                        if let newURL = comps.url {
                            quants[i] = QuantInfo(label: quants[i].label,
                                                  format: quants[i].format,
                                                  sizeBytes: quants[i].sizeBytes,
                                                  downloadURL: newURL,
                                                  sha256: quants[i].sha256,
                                                  configURL: quants[i].configURL ?? URL(string: "https://huggingface.co/\(repo)/raw/main/config.json"))
                        }
                    }
                }
            }

            if quants[i].sizeBytes == 0 {
                if let size = try? await fetchSize(quants[i].downloadURL) {
                    quants[i] = QuantInfo(label: quants[i].label,
                                          format: quants[i].format,
                                          sizeBytes: size,
                                          downloadURL: quants[i].downloadURL,
                                          sha256: quants[i].sha256,
                                          configURL: quants[i].configURL)
                }
            }
        }
        return ModelDetails(id: base.id,
                            summary: base.summary,
                            quants: quants,
                            promptTemplate: base.promptTemplate)

    }

    private func fetchSize(_ url: URL) async throws -> Int64 {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var items = comps.queryItems ?? []
        if !items.contains(where: { $0.name == "download" }) {
            items.append(URLQueryItem(name: "download", value: "1"))
        }
        comps.queryItems = items

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "HEAD"
        if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
        NetworkKillSwitch.track(session: URLSession.shared)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return 0 }

        if let linked = http.value(forHTTPHeaderField: "X-Linked-Size"),
           let len = Int64(linked) { return len }
        if let lenStr = http.value(forHTTPHeaderField: "Content-Length"),
           let len = Int64(lenStr), len > 0 { return len }
        if let range = http.value(forHTTPHeaderField: "Content-Range"),
           let total = range.split(separator: "/").last,
           let len = Int64(total) { return len }
        return http.expectedContentLength > 0 ? http.expectedContentLength : 0
    }

    private func huggingFaceRepoID(from url: URL) -> String? {
        guard let host = url.host, host.contains("huggingface.co") else { return nil }
        var parts = url.path.split(separator: "/").filter { !$0.isEmpty }.map(String.init)
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

    private func extractBitness(from label: String) -> Int? {
        if let r = label.range(of: #"(\d{1,2})(?:\s*bit)?"#, options: .regularExpression) {
            let digits = label[r].replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            return Int(digits)
        }
        return nil
    }

    private static let mlxRepoDetailsCache = MlxRepoDetailsCache()

    public static let defaultEntries: [Entry] = [
        Entry(
            record: ModelRecord(id: "unsloth/Qwen3-1.7B-GGUF",
                                displayName: "Qwen3-1.7B",
                                publisher: "Qwen",
                                summary: "Qwen3-1.7B is a compact and efficient model from the Qwen3 family, suitable for on-device usage with strong general capabilities.",
                                hasInstallableQuant: true,
                                formats: [.gguf, .mlx],
                                installed: false,
                                tags: ["gguf", "mlx", "qwen3"],
                                pipeline_tag: nil),
            details: ModelDetails(
                id: "unsloth/Qwen3-1.7B-GGUF",
                summary: "Qwen3-1.7B is a compact and efficient model from the Qwen3 family, suitable for on-device usage with strong general capabilities.",
                quants: [
                    QuantInfo(label: "Q3_K_M",
                              format: .gguf,
                              sizeBytes: 0,
                              downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q3_K_M.gguf?download=true")!,
                              sha256: nil,
                              configURL: nil),
                    QuantInfo(label: "Q4_K_M",
                              format: .gguf,
                              sizeBytes: 0,
                              downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf?download=true")!,
                              sha256: nil,
                              configURL: nil),
                    QuantInfo(label: "Q6_K",
                              format: .gguf,
                              sizeBytes: 0,
                              downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q6_K.gguf?download=true")!,
                              sha256: nil,
                              configURL: nil),
                    QuantInfo(label: "MLX 4bit",
                              format: .mlx,
                              sizeBytes: 0,
                              downloadURL: URL(string: "https://huggingface.co/mlx-community/Qwen3-1.7B-4bit")!,
                              sha256: nil,
                              configURL: nil)
                ],
                promptTemplate: nil
            )
        )
        ,

        Entry(
            record: ModelRecord(
                id: "unsloth/gemma-3n-E2B-it-GGUF",
                displayName: "Gemma-3n-E2B-it",
                publisher: "Google",
                summary: "Gemma 3n E2B is a lightweight instruction-tuned model from Google's Gemma family, optimized for efficient on-device conversations.",
                hasInstallableQuant: true,
                formats: [.gguf, .mlx],
                installed: false,
                tags: ["gguf", "mlx", "gemma", "gemma3n"],
                pipeline_tag: nil
            ),
            details: ModelDetails(
                id: "unsloth/gemma-3n-E2B-it-GGUF",
                summary: """
Gemma 3n E2B is an instruction-tuned variant of Google's Gemma family built for efficient reasoning on low-resource devices.
Available in GGUF quants (Q3_K_M, Q4_K_M, Q6_K) and an MLX 4-bit build for Apple Silicon.
""",
                quants: [
                    QuantInfo(
                        label: "Q3_K_M",
                        format: .gguf,
                        sizeBytes: 0,
                        downloadURL: URL(string: "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q3_K_M.gguf?download=true")!,
                        sha256: nil,
                        configURL: URL(string: "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/raw/main/config.json")
                    ),
                    QuantInfo(
                        label: "Q4_K_M",
                        format: .gguf,
                        sizeBytes: 0,
                        downloadURL: URL(string: "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q4_K_M.gguf?download=true")!,
                        sha256: nil,
                        configURL: URL(string: "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/raw/main/config.json")
                    ),
                    QuantInfo(
                        label: "Q6_K",
                        format: .gguf,
                        sizeBytes: 0,
                        downloadURL: URL(string: "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q6_K.gguf?download=true")!,
                        sha256: nil,
                        configURL: URL(string: "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/raw/main/config.json")
                    ),
                    QuantInfo(
                        label: "MLX 4bit",
                        format: .mlx,
                        sizeBytes: 0,
                        downloadURL: URL(string: "https://huggingface.co/mlx-community/gemma-3n-E2B-it-4bit")!,
                        sha256: nil,
                        configURL: nil
                    )
                ],
                promptTemplate: nil
            )
        )
        ,

        Entry(
            record: ModelRecord(
                id: "microsoft/phi-4-mini-reasoning",
                displayName: "Phi-4 Mini Reasoning",
                publisher: "microsoft",
                summary: "Phi-4 Mini Reasoning is a lightweight model from the Phi-4 family, tuned for strong reasoning and efficiency across tasks.",
                hasInstallableQuant: true,
                formats: [.gguf, .mlx],
                installed: false,
                tags: ["gguf", "mlx", "phi-4", "reasoning"],
                pipeline_tag: nil
            ),
            details: ModelDetails(
                id: "microsoft/phi-4-mini-reasoning",
                summary: """
Phi-4 Mini Reasoning — a compact model in Microsoft’s Phi-4 line designed for logical reasoning, problem solving, and instruction-following. 
Distributed in efficient GGUF quants (Q3_K_L, Q4_K_M, Q6_K) and an MLX 4-bit variant for Apple Silicon devices.
""",
                quants: [
                    QuantInfo(
                        label: "Q3_K_L",
                        format: .gguf,
                        sizeBytes: 0,
                        downloadURL: URL(string: "https://huggingface.co/lmstudio-community/Phi-4-mini-reasoning-GGUF/resolve/main/Phi-4-mini-reasoning-Q3_K_L.gguf?download=true")!,
                        sha256: nil,
                        configURL: URL(string: "https://huggingface.co/lmstudio-community/Phi-4-mini-reasoning-GGUF/raw/main/config.json")
                    ),
                    QuantInfo(
                        label: "Q4_K_M",
                        format: .gguf,
                        sizeBytes: 0,
                        downloadURL: URL(string: "https://huggingface.co/lmstudio-community/Phi-4-mini-reasoning-GGUF/resolve/main/Phi-4-mini-reasoning-Q4_K_M.gguf?download=true")!,
                        sha256: nil,
                        configURL: URL(string: "https://huggingface.co/lmstudio-community/Phi-4-mini-reasoning-GGUF/raw/main/config.json")
                    ),
                    QuantInfo(
                        label: "Q6_K",
                        format: .gguf,
                        sizeBytes: 0,
                        downloadURL: URL(string: "https://huggingface.co/lmstudio-community/Phi-4-mini-reasoning-GGUF/resolve/main/Phi-4-mini-reasoning-Q6_K.gguf?download=true")!,
                        sha256: nil,
                        configURL: URL(string: "https://huggingface.co/lmstudio-community/Phi-4-mini-reasoning-GGUF/raw/main/config.json")
                    ),
                    QuantInfo(
                        label: "MLX 4bit",
                        format: .mlx,
                        sizeBytes: 0,
                        downloadURL: URL(string: "https://huggingface.co/lmstudio-community/Phi-4-mini-reasoning-MLX-4bit")!,
                        sha256: nil,
                        configURL: nil
                    )
                ],
                promptTemplate: nil
            )
        )
    ]
}
