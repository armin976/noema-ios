// HuggingFaceMetadataCache.swift
import Foundation

struct ModelHubMeta: Codable {
    let id: String
    let author: String?
    let pipelineTag: String?
    let tags: [String]?
    let gguf: GGUFMeta?

    struct GGUFMeta: Codable {
        let architecture: String?
        let context_length: Int?
        let chat_template: String?
    }

    var isVisionByPipeline: Bool {
        guard let p = pipelineTag?.lowercased() else { return false }
        return p == "image-text-to-text"
    }
    
    var isVision: Bool {
        // Treat as vision if pipeline tag is exactly "image-text-to-text"
        // or if tags include "image-text-to-text"
        if isVisionByPipeline { return true }
        if let tags, tags.contains(where: { $0.lowercased() == "image-text-to-text" }) { return true }
        return false
    }
}

private actor HFMetadataSingleFlight {
    static let shared = HFMetadataSingleFlight()
    private var inflight: [String: Task<ModelHubMeta?, Never>] = [:]
    
    func run(key: String, operation: @escaping @Sendable () async -> ModelHubMeta?) async -> ModelHubMeta? {
        if let existing = inflight[key] { return await existing.value }
        let task = Task { await operation() }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }
}

enum HuggingFaceMetadataCache {
    static func cacheDir(repoId: String) -> URL {
        var base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        base.appendPathComponent("ModelCards", isDirectory: true)
        for comp in repoId.split(separator: "/") {
            base.appendPathComponent(String(comp), isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func cached(repoId: String) -> ModelHubMeta? {
        let url = cacheDir(repoId: repoId).appendingPathComponent("hub.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ModelHubMeta.self, from: data)
    }

    static func fetch(repoId: String, token: String?) async -> ModelHubMeta? {
        let escaped = repoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoId
        guard let url = URL(string: "https://huggingface.co/api/models/\(escaped)") else { return nil }
        do {
            let (data, resp) = try await HFHubRequestManager.shared.data(for: url,
                                                                         token: token,
                                                                         accept: "application/json",
                                                                         timeout: 10)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            // Minimal decode mapping the few fields we need
            let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let id = (raw?["id"] as? String) ?? repoId
            let author = raw?["author"] as? String
            let pipeline = (raw?["pipeline_tag"] as? String) ?? (raw?["cardData"] as? [String: Any])?["pipeline_tag"] as? String
            let tags = raw?["tags"] as? [String]
            var gguf: ModelHubMeta.GGUFMeta? = nil
            if let g = raw?["gguf"] as? [String: Any] {
                let arch = g["architecture"] as? String
                let ctx = g["context_length"] as? Int
                let tmpl = g["chat_template"] as? String
                gguf = .init(architecture: arch, context_length: ctx, chat_template: tmpl)
            }
            return ModelHubMeta(id: id, author: author, pipelineTag: pipeline, tags: tags, gguf: gguf)
        } catch {
            return nil
        }
    }

    static func fetchAndCache(repoId: String, token: String?) async -> ModelHubMeta? {
        let key = repoId + "|" + (token ?? "")
        return await HFMetadataSingleFlight.shared.run(key: key) {
            guard let meta = await fetch(repoId: repoId, token: token) else { return nil }
            let dir = cacheDir(repoId: repoId)
            let jsonURL = dir.appendingPathComponent("hub.json")
            if let data = try? JSONEncoder().encode(meta) {
                try? data.write(to: jsonURL)
            }
            if let chat = meta.gguf?.chat_template, !chat.isEmpty {
                let tmplURL = dir.appendingPathComponent("chat_template.txt")
                try? chat.data(using: .utf8)?.write(to: tmplURL)
            }
            return meta
        }
    }

    static func saveToModelDir(meta: ModelHubMeta, modelID: String, format: ModelFormat) {
        let dir = InstalledModelsStore.baseDir(for: format, modelID: modelID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let jsonURL = dir.appendingPathComponent("hub.json")
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: jsonURL)
        }
        if let chat = meta.gguf?.chat_template, !chat.isEmpty {
            let tmplURL = dir.appendingPathComponent("chat_template.txt")
            try? chat.data(using: .utf8)?.write(to: tmplURL)
        }
    }
}


