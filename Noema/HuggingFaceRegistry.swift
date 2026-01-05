// HuggingFaceRegistry.swift
import Foundation

public final class HuggingFaceRegistry: ModelRegistry, @unchecked Sendable {

    private let session: URLSession
    private let token: String?

    public init(session: URLSession = .shared, token: String? = nil) {
        self.session = session
        if let t = token?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            self.token = t
        } else {
            self.token = nil
        }
    }

    enum RegistryError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code):
                return "Server error (HTTP \(code))"
            }
        }
    }

    // MARK: - ModelRegistry
    public func curated() async throws -> [ModelRecord] { [] }

    public func searchStream(query: String, page: Int, includeVisionModels: Bool = true, visionOnly: Bool = false) -> AsyncThrowingStream<ModelRecord, Error> {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .init { $0.finish() } }
        let offset = page * 50
        
        // Make search more flexible by removing spaces for model names like "gemma 3 4b"
        // This helps match models named "gemma-3-4b" or "gemma3-4b"
        let searchQuery = trimmed
        
        // Build URLs. When a specific pipeline is provided we use the
        // `filter` query parameter. In "All" explore mode we must avoid
        // adding any pipeline filter so the Hub searches across all tasks.
        func makeURL(pipeline: String) -> URL {
            var c = URLComponents(string: "https://huggingface.co/api/models")!
            c.queryItems = [
                URLQueryItem(name: "search", value: searchQuery),
                URLQueryItem(name: "filter", value: pipeline),
                URLQueryItem(name: "sort", value: "downloads"),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "cardData", value: "true")
            ]
            return c.url!
        }

        func makeURLAllPipelines() -> URL {
            var c = URLComponents(string: "https://huggingface.co/api/models")!
            c.queryItems = [
                URLQueryItem(name: "search", value: searchQuery),
                URLQueryItem(name: "sort", value: "downloads"),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "cardData", value: "true")
            ]
            return c.url!
        }
        
        let urlText = makeURL(pipeline: "text-generation")
        let urlVLM = makeURL(pipeline: "image-text-to-text")
        
        // Determine which URLs to fetch based on parameters
        let urlsToFetch: [URL]
        if visionOnly {
            // Vision mode → explicitly filter to VLM pipeline
            urlsToFetch = [urlVLM]
        } else if includeVisionModels {
            // Explore "All" mode → do NOT add a text-generation filter
            // (and also avoid the VLM-specific filter). Query across all pipelines.
            urlsToFetch = [makeURLAllPipelines()]
        } else {
            // Text mode → explicitly filter to text-generation pipeline
            urlsToFetch = [urlText]
        }
        
        return .init { continuation in
            let task = Task {
                do {
                    struct Entry: Decodable {
                        let modelId: String
                        let author: String?
                        let tags: [String]?
                        let pipeline_tag: String?
                        let cardData: Card?
                        struct Card: Decodable { let summary: String?; let pipeline_tag: String? }

                        enum CodingKeys: String, CodingKey { case modelId, id, author, tags, pipeline_tag, cardData }

                        init(from decoder: Decoder) throws {
                            let container = try decoder.container(keyedBy: CodingKeys.self)
                            if let mid = try container.decodeIfPresent(String.self, forKey: .modelId) {
                                self.modelId = mid
                            } else {
                                self.modelId = try container.decode(String.self, forKey: .id)
                            }
                            self.author = try container.decodeIfPresent(String.self, forKey: .author)
                            self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
                            let topPipeline = try container.decodeIfPresent(String.self, forKey: .pipeline_tag)
                            self.cardData = try container.decodeIfPresent(Card.self, forKey: .cardData)
                            self.pipeline_tag = topPipeline ?? self.cardData?.pipeline_tag
                        }
                    }
                    
                    var combinedData: [Data] = []
                    
                    // Fetch from all specified URLs
                    for url in urlsToFetch {
                        let data = try await self.data(from: url)
                        combinedData.append(data.0)
                    }
                    
                    // Process both result sets
                    var seen = Set<String>()
                    for rawData in combinedData {
                        guard let pageResults = try? JSONDecoder().decode([Entry].self, from: rawData) else {
                            continue
                        }
                        print("[registry] search \(trimmed) page \(page) → \(pageResults.count)")
                        for entry in pageResults {
                            if !seen.insert(entry.modelId).inserted { continue }
                            let formats = Self.inferFormats(tags: entry.tags ?? [], id: entry.modelId, pipelineTag: entry.pipeline_tag)
                            let effectiveFormats = formats
                            let owner = entry.modelId.split(separator: "/").first.map(String.init) ?? (entry.author ?? "")
                            let record = ModelRecord(
                                id: entry.modelId,
                                displayName: Self.prettyName(from: entry.modelId),
                                publisher: owner,
                                summary: entry.cardData?.summary,
                                hasInstallableQuant: true,
                                formats: effectiveFormats,
                                installed: false,
                                tags: entry.tags,
                                pipeline_tag: entry.pipeline_tag
                            )
                            continuation.yield(record)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func details(for id: String) async throws -> ModelDetails {
        var comps = URLComponents(string: "https://huggingface.co/api/models/\(id)")!
        comps.queryItems = [URLQueryItem(name: "full", value: "1"), URLQueryItem(name: "cardData", value: "true")]
        let (data, _) = try await data(from: comps.url!)
        struct Meta: Decodable { let modelId: String; let author: String?; let cardData: Card?; let siblings: [Sibling]?; struct Card: Decodable { let summary: String? }; struct Sibling: Decodable { let rfilename: String; let size: Int?; let lfs: LFS?; struct LFS: Decodable { let sha256: String?; let size: Int? } } }
        let meta = try JSONDecoder().decode(Meta.self, from: data)
        let files = (meta.siblings ?? []).map { RepoFile(path: $0.rfilename, size: Int64($0.lfs?.size ?? $0.size ?? 0), sha256: $0.lfs?.sha256) }
        var quants = QuantExtractor.extract(from: files, repoID: id)
        let cfgURL = URL(string: "https://huggingface.co/\(id)/raw/main/config.json")
        for i in quants.indices {
            if quants[i].sizeBytes == 0 {
                if let size = try? await fetchSize(quants[i].downloadURL) {
                    quants[i] = QuantInfo(label: quants[i].label,
                                         format: quants[i].format,
                                         sizeBytes: size,
                                         downloadURL: quants[i].downloadURL,
                                         sha256: quants[i].sha256,
                                         configURL: cfgURL)
                }
            } else if quants[i].configURL == nil {
                quants[i] = QuantInfo(label: quants[i].label,
                                     format: quants[i].format,
                                     sizeBytes: quants[i].sizeBytes,
                                     downloadURL: quants[i].downloadURL,
                                     sha256: quants[i].sha256,
                                     configURL: cfgURL)
            }
        }
        let prompt: String? = nil
        return ModelDetails(id: meta.modelId,
                            summary: meta.cardData?.summary,
                            quants: quants,
                            promptTemplate: prompt)
    }

    // MARK: - helpers
    private func fetchRecord(id: String) async throws -> ModelRecord? {
        do {
            let details = try await details(for: id)
            let fmts = Set(details.quants.map { $0.format })
            return ModelRecord(id: id,
                              displayName: Self.prettyName(from: id),
                              publisher: "",
                              summary: details.summary,
                              hasInstallableQuant: !details.quants.isEmpty,
                              formats: fmts,
                              installed: false,
                              tags: nil,
                              pipeline_tag: nil)
        } catch { return nil }
    }

    private func data(from url: URL) async throws -> (Data, URLResponse) {
        print("[registry] GET \(url.absoluteString)")
        let (data, resp) = try await HFHubRequestManager.shared.data(for: url,
                                                                     token: token,
                                                                     accept: "application/json")
        if let http = resp as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            // Surface HTTP status code for easier debugging.
            print("[registry] HTTP \(http.statusCode) for \(url.path)")
            throw RegistryError.badStatus(http.statusCode)
        }
        return (data, resp)
    }


    private func fetchSize(_ url: URL) async throws -> Int64 {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var items = comps.queryItems ?? []
        if !items.contains(where: { $0.name == "download" }) {
            items.append(URLQueryItem(name: "download", value: "1"))
        }
        comps.queryItems = items

        let (_, resp) = try await HFHubRequestManager.shared.data(for: comps.url!,
                                                                  token: token,
                                                                  method: "HEAD")
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

    private static func prettyName(from id: String) -> String {
        let base = id.split(separator: "/").last.map(String.init) ?? id
        var cleaned = base.replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?i)gguf", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?i)ggml", with: "", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }

    private static func inferFormats(tags: [String], id: String, pipelineTag: String? = nil) -> Set<ModelFormat> {
        var result: Set<ModelFormat> = []
        let lowerTags = tags.map { $0.lowercased() }
        if lowerTags.contains(where: { $0.contains("gguf") || $0.contains("ggml") }) {
            result.insert(.gguf)
        }
        // Treat MLX explicitly tagged repositories as MLX, and also
        // heuristically include well-known publishers who host MLX conversions.
        // This mirrors Explore filtering behavior so MLX mode surfaces expected results.
        if lowerTags.contains(where: { $0.contains("mlx") })
            || id.hasPrefix("mlx-community/")
            || id.hasPrefix("lmstudio-community/") {
            result.insert(.mlx)
        }
        return result
    }

}
