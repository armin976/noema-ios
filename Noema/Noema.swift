// Noema.swift
//  Noema.swift
//  Noema – iPhone‑first local‑LLM chat (verbose console logging)
//
//  • First launch ⇒ one‑tap download (Qwen3‑1.7B GGUF from Hugging Face)
//  • After that the model loads 100% offline from <Documents>/LocalLLMModels/…
//
//
//  Requires Swift Concurrency (iOS 17+).

import SwiftUI
import Foundation
import Combine
import UIKit
import PhotosUI
@_exported import Foundation
import AutoFlow

// Import RollingThought functionality through NoemaPackages
import NoemaPackages

// Removed LocalLLMClient MLX path in favor of mlx-swift/mlx-swift-examples integration
// Using our own llama.cpp implementation instead of LocalLLMClientLlama
import LeapSDK
#if canImport(MLX)
import MLX
#endif

// MARK: –– Experience coordination ------------------------------------------

@MainActor
// MARK: –– Model metadata ----------------------------------------------------
// MARK: –– FileManager helpers ----------------------------------------------
// MARK: –– Download screen ---------------------------------------------------
struct DownloadView: View {
    @ObservedObject var vm: ModelDownloader

    var body: some View {
        VStack(spacing: 20) {
            Text("First‑time setup: download the Qwen‑1.7B model and embeddings.\nWi‑Fi recommended.")
                .multilineTextAlignment(.center)

            switch vm.state {
            case .idle:
                Button("Download Models") { vm.start() }
                    .buttonStyle(.borderedProminent)

            case .downloading(let p):
                VStack(spacing: 12) {
                    Text("Downloading…")
                        .font(.headline)
                    ModernDownloadProgressView(progress: p, speed: nil)
                }

            case .failed(let msg):
                VStack(spacing: 12) {
                    Text("⚠️ " + msg).font(.caption)
                    Button("Retry") { vm.start() }
                }

            case .finished:
                ProgressView().progressViewStyle(.circular)
                Text("Preparing…").font(.caption)
            }
        }
        .padding()
    }
}

// MARK: –– Chat view‑model ---------------------------------------------------
// Helper utilities for MLX repo inference and tokenizer fetching
@MainActor
private func inferRepoID(from directory: URL) -> String? {
    // Prefer explicit repo.txt if present
    let explicit = directory.appendingPathComponent("repo.txt")
    if let data = try? Data(contentsOf: explicit), let s = String(data: data, encoding: .utf8) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    // Typical layout: .../LocalLLMModels/<owner>/<repo>
    let owner = directory.deletingLastPathComponent().lastPathComponent
    let repo  = directory.lastPathComponent
    if !owner.isEmpty, owner != "LocalLLMModels" { return owner + "/" + repo }
    // Legacy single-component folder names
    if repo.contains("/") { return repo }
    if repo.contains("_") { return repo.replacingOccurrences(of: "_", with: "/") }
    return repo
}

@MainActor
private func fetchTokenizer(into dir: URL, repoID: String) async {
    let defaults = UserDefaults.standard
    let token = defaults.string(forKey: "huggingFaceToken")
    func request(_ url: URL, accept: String) async throws -> Data? {
        if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
        var req = URLRequest(url: url)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if let t = token, !t.isEmpty { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        NetworkKillSwitch.track(session: URLSession.shared)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) { return data }
        return nil
    }
    func isLFSPointerData(_ data: Data) -> Bool {
        if data.count > 4096 { return false }
        guard let s = String(data: data, encoding: .utf8) else { return false }
        let lower = s.lowercased()
        return lower.contains("git-lfs") || lower.contains("oid sha256:")
    }
    // Try to derive tokenizer path from local config.json if it references a subpath
    if let cfgData = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
       let cfg = try? JSONSerialization.jsonObject(with: cfgData) as? [String: Any] {
        let keys = ["tokenizer_file", "tokenizer_json", "tokenizer", "tokenizer_path"]
        for k in keys {
            if let rel = cfg[k] as? String, rel.lowercased().contains("tokenizer") {
                let candidates = [
                    URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(rel)?download=1"),
                    URL(string: "https://huggingface.co/\(repoID)/raw/main/\(rel)")
                ].compactMap { $0 }
                for u in candidates {
                    if let data = try? await request(u, accept: "application/json"), data.count > 0, !isLFSPointerData(data) {
                        try? data.write(to: dir.appendingPathComponent("tokenizer.json"))
                        return
                    }
                }
            }
        }
    }
    // Try tokenizer.json via resolve first (works with LFS), then raw as fallback
    if let data = try? await request(URL(string: "https://huggingface.co/\(repoID)/resolve/main/tokenizer.json?download=1")!, accept: "application/json"), data.count > 0, !isLFSPointerData(data) {
        try? data.write(to: dir.appendingPathComponent("tokenizer.json"))
        return
    }
    if let data = try? await request(URL(string: "https://huggingface.co/\(repoID)/raw/main/tokenizer.json")!, accept: "application/json"), data.count > 0, !isLFSPointerData(data) {
        try? data.write(to: dir.appendingPathComponent("tokenizer.json"))
        return
    }
    // Try known SentencePiece names (prefer resolve first)
    for name in ["tokenizer.model", "spiece.model", "sentencepiece.bpe.model"] {
        if let data = try? await request(URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(name)?download=1")!, accept: "application/octet-stream"), data.count > 0 {
            try? data.write(to: dir.appendingPathComponent(name))
            return
        }
        if let data = try? await request(URL(string: "https://huggingface.co/\(repoID)/raw/main/\(name)")!, accept: "application/octet-stream"), data.count > 0 {
            try? data.write(to: dir.appendingPathComponent(name))
            return
        }
    }
}

@MainActor final class AppModelManager: ObservableObject {
    private let store: InstalledModelsStore
    @Published var downloadedModels: [LocalModel] = []
    @Published var loadedModel: LocalModel?
    @Published var lastUsedModel: LocalModel?
    @Published var modelSettings: [String: ModelSettings] = [:]
    @Published var downloadedDatasets: [LocalDataset] = []
    @Published var activeDataset: LocalDataset?
    @Published var loadingModelName: String?  // Track model name during loading
    private var favourites: Set<String> = []
    fileprivate var datasetManager: DatasetManager?
    private var cancellables: Set<AnyCancellable> = []

    init(store: InstalledModelsStore = InstalledModelsStore()) {
        self.store = store
        store.migrateLeapBundles()
        store.migratePaths()
        store.rehomeIfMissing()
        if let fav = UserDefaults.standard.array(forKey: "favouriteModels") as? [String] {
            favourites = Set(fav)
        }
        downloadedModels = LocalModel.loadInstalled(store: store)
            .removingDuplicateURLs()
            .map { model in
                var m = model
                m.isFavourite = favourites.contains(m.url.path)
                return m
            }
        updateLastUsedModel()
        // Load durable settings first from Keychain+mirror; fall back to legacy UserDefaults once then migrate
        let durable = ModelSettingsStore.load()
        if !durable.isEmpty {
            // Convert durable keyed by "modelID|quant" into path-keyed map for in-memory use later
            var map: [String: ModelSettings] = [:]
            for item in store.all() {
                let key = item.modelID + "|" + item.quantLabel
                if let s = durable[key] { map[item.url.path] = s }
            }
            modelSettings = map
        } else if let data = UserDefaults.standard.data(forKey: "modelSettings"),
                  let decoded = try? JSONDecoder().decode([String: ModelSettings].self, from: data) {
            modelSettings = decoded
            // Attempt one-time migration into durable store keyed by (modelID|quant)
            var byIDQuant: [String: ModelSettings] = [:]
            for item in store.all() {
                if let s = decoded[item.url.path] {
                    byIDQuant[item.modelID + "|" + item.quantLabel] = s
                }
            }
            ModelSettingsStore.save(byIDQuant)
        }
        scanLayersIfNeeded()
    }

    func refresh() {
        store.reload()
        store.migrateLeapBundles()
        store.migratePaths()
        store.rehomeIfMissing()
        downloadedModels = LocalModel.loadInstalled(store: store)
            .removingDuplicateURLs()
            .map { model in
                var m = model
                m.isFavourite = favourites.contains(m.url.path)
                return m
            }
        updateLastUsedModel()
        scanLayersIfNeeded()
        scanCapabilitiesIfNeeded()
        datasetManager?.reloadFromDisk()
    }

    private func updateLastUsedModel() {
        lastUsedModel = downloadedModels
            .filter { $0.lastUsedDate != nil }
            .sorted { $0.lastUsedDate! > $1.lastUsedDate! }
            .first
    }
    /// Set the given model as recently used and mark it as loaded.
    func markModelUsed(_ model: LocalModel) {
        var m = model
        m.lastUsedDate = Date()
        store.updateLastUsed(modelID: m.modelID, quantLabel: m.quant, date: m.lastUsedDate!)
        if let idx = downloadedModels.firstIndex(where: { $0.id == model.id }) {
            downloadedModels[idx] = m
        } else {
            downloadedModels.append(m)
        }
        loadedModel = m
        lastUsedModel = m
    }
    
    func setCapabilities(modelID: String, quant: String, isMultimodal: Bool, isToolCapable: Bool) {
        store.updateCapabilities(modelID: modelID, quantLabel: quant, isMultimodal: isMultimodal, isToolCapable: isToolCapable)
        refresh()
    }

    func bind(datasetManager: DatasetManager) {
        guard self.datasetManager !== datasetManager else { return }
        self.datasetManager = datasetManager
        datasetManager.$datasets
            .sink { [weak self] ds in
                self?.downloadedDatasets = ds
                // Don't automatically set activeDataset - user must explicitly select
                // self?.activeDataset = ds.first { $0.isSelected }
            }
            .store(in: &cancellables)
    }

    func setActiveDataset(_ ds: LocalDataset?) {
        datasetManager?.select(ds)
        // Update activeDataset immediately
        activeDataset = ds
        // Persist selection for background gates
        let d = UserDefaults.standard
        if let id = ds?.datasetID, !id.isEmpty {
            d.set(id, forKey: "selectedDatasetID")
        } else {
            d.set("", forKey: "selectedDatasetID")
        }
    }

    /// Adds a newly installed model to the store and refreshes the list.
    func install(_ model: InstalledModel) {
        store.add(model)
        refresh()
    }

    func delete(_ model: LocalModel) {
        let fm = FileManager.default
        switch model.format {
        case .gguf:
            try? fm.removeItem(at: model.url)
            let dir = model.url.deletingLastPathComponent()
            // Remove DeepSeek marker cache sidecar if present to keep directory tidy
            let dsCache = dir.appendingPathComponent("ds_markers.cache.json")
            if fm.fileExists(atPath: dsCache.path) {
                try? fm.removeItem(at: dsCache)
            }
            if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
               !items.contains(where: { $0.pathExtension.lowercased() == "gguf" }) {
                try? fm.removeItem(at: dir)
            }
        default:
            try? fm.removeItem(at: model.url)
        }
        store.remove(modelID: model.modelID, quantLabel: model.quant)
        refresh()
        if loadedModel?.id == model.id { loadedModel = nil }
        if lastUsedModel?.id == model.id { lastUsedModel = nil }
        if UserDefaults.standard.string(forKey: "defaultModelPath") == model.url.path {
            UserDefaults.standard.set("", forKey: "defaultModelPath")
        }
    }

    func settings(for model: LocalModel) -> ModelSettings {
        if let existing = modelSettings[model.url.path] {
            return existing
        }
        var s = ModelSettings.fromConfig(for: model)
        // Default to sentinel (-1) meaning "all layers" for GGUF unless already set elsewhere.
        if model.format == .gguf && s.gpuLayers == 0 {
            s.gpuLayers = -1
        }
        modelSettings[model.url.path] = s
        return s
    }

    func updateSettings(_ settings: ModelSettings, for model: LocalModel) {
        modelSettings[model.url.path] = settings
        // Persist to legacy store for backwards compatibility
        if let data = try? JSONEncoder().encode(modelSettings) {
            UserDefaults.standard.set(data, forKey: "modelSettings")
        }
        // Persist to durable store keyed by (modelID|quant)
        ModelSettingsStore.save(settings: settings, forModelID: model.modelID, quantLabel: model.quant)
    }

    func toggleFavourite(_ model: LocalModel) {
        if favourites.contains(model.url.path) {
            favourites.remove(model.url.path)
        } else {
            favourites.insert(model.url.path)
        }
        UserDefaults.standard.set(Array(favourites), forKey: "favouriteModels")
        if let idx = downloadedModels.firstIndex(where: { $0.id == model.id }) {
            downloadedModels[idx].isFavourite.toggle()
            store.updateFavorite(modelID: model.modelID, quantLabel: model.quant, fav: downloadedModels[idx].isFavourite)
        } else {
            store.updateFavorite(modelID: model.modelID, quantLabel: model.quant, fav: favourites.contains(model.url.path))
        }
    }

    private func scanLayersIfNeeded() {
        let pending = downloadedModels.filter { $0.totalLayers == 0 }
        guard !pending.isEmpty else { return }
        let models = pending
        Task.detached(priority: .utility) { [weak self] in
            for model in models {
                let count = ModelScanner.layerCount(for: model.url, format: model.format)
                await self?.applyLayerCount(count, to: model)
                // Stagger to avoid startup spikes
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    private func scanCapabilitiesIfNeeded() {
        let token = UserDefaults.standard.string(forKey: "huggingFaceToken")
        // Prepare a list of models that still need capability detection
        let candidates: [(id: String, quant: String)] = downloadedModels.compactMap { model in
            // Skip if we already have capability info
            if model.isMultimodal || model.isToolCapable { return nil }
            if let installed = store.all().first(where: { $0.modelID == model.modelID && $0.quantLabel == model.quant }),
               (installed.isMultimodal || installed.isToolCapable) { return nil }
            return (model.modelID, model.quant)
        }
        guard !candidates.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            for (modelID, quant) in candidates {
                // Only use pipeline tag for multimodality
                let meta = await HuggingFaceMetadataCache.fetchAndCache(repoId: modelID, token: token)
                var isVision = meta?.isVision ?? false
                if !isVision {
                    // Fallback to on-disk heuristics for missing/incorrect tags
                    let dir = InstalledModelsStore.baseDir(for: .gguf, modelID: modelID)
                    if let gguf = InstalledModelsStore.firstGGUF(in: dir) {
                        isVision = ChatVM.guessLlamaVisionModel(from: gguf)
                    } else {
                        // Try MLX dir
                        let mlxDir = InstalledModelsStore.baseDir(for: .mlx, modelID: modelID)
                        isVision = MLXBridge.isVLMModel(at: mlxDir)
                    }
                }
                var toolCap = await ToolCapabilityDetector.isToolCapable(repoId: modelID, token: token)
                if toolCap == false {
                    // Local fallback: prefer GGUF file or MLX directory
                    let ggufDir = InstalledModelsStore.baseDir(for: .gguf, modelID: modelID)
                    if let gguf = InstalledModelsStore.firstGGUF(in: ggufDir) {
                        toolCap = ToolCapabilityDetector.isToolCapableLocal(url: gguf, format: .gguf)
                    } else {
                        let mlxDir = InstalledModelsStore.baseDir(for: .mlx, modelID: modelID)
                        toolCap = ToolCapabilityDetector.isToolCapableLocal(url: mlxDir, format: .mlx)
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.store.updateCapabilities(modelID: modelID, quantLabel: quant, isMultimodal: isVision, isToolCapable: toolCap)
                    // Update in-memory list in place to avoid full refresh loops
                    if let idx = self.downloadedModels.firstIndex(where: { $0.modelID == modelID && $0.quant == quant }) {
                        self.downloadedModels[idx].isMultimodal = isVision
                        self.downloadedModels[idx].isToolCapable = toolCap
                    }
                }
                // Stagger requests
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func applyLayerCount(_ count: Int, to model: LocalModel) {
        if let idx = downloadedModels.firstIndex(where: { $0.id == model.id }) {
            downloadedModels[idx].totalLayers = count
            store.updateLayers(modelID: model.modelID, quantLabel: model.quant, layers: count)
        }
    }
}

@MainActor final class ChatVM: ObservableObject {
    // Progress tracker for model loading
    @Published var loadingProgressTracker = ModelLoadingProgressTracker()
    struct Msg: Identifiable, Equatable, Codable {
        struct Perf: Equatable, Codable {
            var tokenCount: Int
            var avgTokPerSec: Double
            var timeToFirst: Double
        }
        
        struct Citation: Equatable, Codable {
            let text: String
            let source: String?
        }

        // Web tool metadata captured from TOOL_RESULT output
        struct WebHit: Equatable, Codable {
            let id: String
            let title: String
            let snippet: String
            let url: String
            let engine: String
            let score: Double
        }
        
        // Generic tool call metadata for UI display
        struct ToolCall: Equatable, Codable, Identifiable {
            let id: UUID
            let toolName: String
            let displayName: String
            let iconName: String
            let requestParams: [String: AnyCodable]
            let result: String?
            let error: String?
            let timestamp: Date
            
            init(id: UUID = UUID(), toolName: String, displayName: String, iconName: String, requestParams: [String: AnyCodable], result: String? = nil, error: String? = nil, timestamp: Date = Date()) {
                self.id = id
                self.toolName = toolName
                self.displayName = displayName
                self.iconName = iconName
                self.requestParams = requestParams
                self.result = result
                self.error = error
                self.timestamp = timestamp
            }
        }

        let id: UUID
        let role: String
        var text: String
        var timestamp: Date
        var perf: Perf?
        var streaming: Bool = false
        var retrievedContext: String?
        var citations: [Citation]?
        var usedWebSearch: Bool?
        var webHits: [WebHit]?
        var webError: String?
        var imagePaths: [String]?
        var toolCalls: [ToolCall]?

        init(id: UUID = UUID(), role: String, text: String, timestamp: Date = Date(), perf: Perf? = nil, streaming: Bool = false) {
            self.id = id
            self.role = role
            self.text = text
            self.timestamp = timestamp
            self.perf = perf
            self.streaming = streaming
        }

        enum CodingKeys: String, CodingKey { case id, role, text, timestamp, perf, retrievedContext, citations, usedWebSearch, webHits, webError, imagePaths, toolCalls }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            role = try c.decode(String.self, forKey: .role)
            text = try c.decode(String.self, forKey: .text)
            timestamp = (try? c.decode(Date.self, forKey: .timestamp)) ?? Date()
            perf = try? c.decode(Perf.self, forKey: .perf)
            retrievedContext = try? c.decode(String.self, forKey: .retrievedContext)
            citations = try? c.decode([Citation].self, forKey: .citations)
            usedWebSearch = try? c.decode(Bool.self, forKey: .usedWebSearch)
            webHits = try? c.decode([WebHit].self, forKey: .webHits)
            webError = try? c.decode(String.self, forKey: .webError)
            imagePaths = try? c.decode([String].self, forKey: .imagePaths)
            toolCalls = try? c.decode([ToolCall].self, forKey: .toolCalls)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(role, forKey: .role)
            try c.encode(text, forKey: .text)
            try c.encode(timestamp, forKey: .timestamp)
            try c.encodeIfPresent(perf, forKey: .perf)
            try c.encodeIfPresent(retrievedContext, forKey: .retrievedContext)
            try c.encode(citations, forKey: .citations)
            try c.encodeIfPresent(usedWebSearch, forKey: .usedWebSearch)
            try c.encodeIfPresent(webHits, forKey: .webHits)
            try c.encodeIfPresent(webError, forKey: .webError)
            try c.encodeIfPresent(imagePaths, forKey: .imagePaths)
            try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        }
    }

    // Expose Msg.ToolCall as ChatVM.ToolCall for convenience
    typealias ToolCall = Msg.ToolCall

    struct Session: Identifiable, Equatable, Codable {
        let id: UUID
        var title: String
        var messages: [Msg]
        var isFavorite: Bool = false
        var date: Date
        var datasetID: String?

        init(id: UUID = UUID(), title: String, messages: [Msg], isFavorite: Bool = false, date: Date, datasetID: String? = nil) {
            self.id = id
            self.title = title
            self.messages = messages
            self.isFavorite = isFavorite
            self.date = date
            self.datasetID = datasetID
        }
    }
    
    fileprivate enum Piece: Identifiable {
        case text(String)
        case think(String, done: Bool)
        case code(String, language: String?)
        // Inline placeholder where a tool response should render instead of raw JSON
        case tool(Int) // Index of the tool call in the message's toolCalls array
        var id: UUID { UUID() }
    }

    enum InjectionStage { case none, deciding, decided, processing, predicting }
    enum InjectionMethod { case full, rag }

    @Published var sessions: [Session] = [] {
        didSet { saveSessions() }
    }
    private var suppressAutoDatasetRestore = false
    @Published var activeSessionID: Session.ID? {
        didSet {
            saveSessions()
            if !suppressAutoDatasetRestore { applySessionDataset() }
            // Recreate rolling thought view models when switching sessions
            recreateRollingThoughtViewModels()
        }
    }
    @Published var prompt: String = ""
    @Published var loading  = false {
        didSet {
            if loading {
                loadingProgressTracker.startLoading(for: loadedFormat ?? .gguf)
            } else {
                loadingProgressTracker.completeLoading()
            }
        }
    }
    @Published var stillLoading = false
    @Published var loadError: String?
    @Published private(set) var modelLoaded = false
    @Published var injectionStage: InjectionStage = .none
    @Published var injectionMethod: InjectionMethod?
    @Published var supportsImageInput: Bool = false
    @Published var pendingImageURLs: [URL] = []

    /// Custom prompt template loaded from model configuration
    var promptTemplate: String?
    
    /// Rolling thought view models for active thinking boxes
    @Published var rollingThoughtViewModels: [String: RollingThoughtViewModel] = [:]
    
    /// Token stream adapter for rolling thoughts
    private struct ChatTokenStream: TokenStream {
        typealias AsyncTokenSequence = AsyncStream<String>
        let stream: AsyncTokenSequence

        func tokens() -> AsyncTokenSequence {
            return stream
        }

        init(tokens: AsyncTokenSequence) {
            self.stream = tokens
        }
    }

    @AppStorage("systemPreset") private var systemPresetRaw = SystemPreset.general.rawValue

    // Expose whether current model supports tool calling (disallow for SLM)
    public var currentModelFormat: ModelFormat? { loadedFormat }
    public var isSLMModel: Bool { loadedFormat == .slm }
    var supportsToolsFlag: Bool { loadedFormat != .slm }

    /// Returns the active system prompt text based on user settings.
    var systemPromptText: String {
        // If a dataset is active (RAG), prefer the RAG preset and exclude tool guidance.
        if let ds = modelManager?.activeDataset, ds.isIndexed, loadedFormat != .some(.slm) {
            // Ensure no accidental anti-reasoning directives like "/nothink" are present.
            var base = SystemPreset.rag.text
            base = sanitizeSystemPrompt(base)
            // Vision guard: when using a vision-capable model without any attached images,
            // explicitly instruct the model to behave as text-only to avoid hallucinated visuals.
            if supportsImageInput && pendingImageURLs.isEmpty {
                base += "\n\nIMPORTANT: No image is provided unless explicitly attached. Answer as a text-only assistant. Do not infer, imagine, or describe any images."
            } else if supportsImageInput && !pendingImageURLs.isEmpty {
                let n = pendingImageURLs.count
                let plural = n == 1 ? "image" : "images"
                base += "\n\nVision: \(n) \(plural) attached. Use them to answer the question. Describe only what is actually present. If unsure, say you are unsure. Do not invent details."
            }
            return base
        }
        // Otherwise, use the general preset and append web tool guidance if available.
        var t = sanitizeSystemPrompt(SystemPreset.general.text)
        // Vision guard for general chats with VLMs when no image is attached
        if supportsImageInput && pendingImageURLs.isEmpty {
            t += "\n\nIMPORTANT: No image is provided unless explicitly attached. Answer as a text-only assistant. Do not infer, imagine, or describe any images."
        } else if supportsImageInput && !pendingImageURLs.isEmpty {
            let n = pendingImageURLs.count
            let plural = n == 1 ? "image" : "images"
            t += "\n\nVision: \(n) \(plural) attached. Use them to answer the question. Describe only what is actually present. If unsure, say you are unsure. Do not invent details."
        }
        if WebToolGate.isAvailable(currentFormat: loadedFormat) {
            let instr = "**WEB SEARCH (ARMED)**: Use the web search tool ONLY if the query needs fresh/current info; otherwise answer directly.\n\n**CALL FORMAT (JSON or XML)**:\n- JSON (respond with this object only; no backticks, no prose):\n{\n  \"tool_name\": \"noema.web.retrieve\",\n  \"arguments\": {\n    \"query\": \"...\",\n    \"count\": 3,\n    \"safesearch\": \"moderate\"\n  }\n}\n\n- XML (for models like Qwen; the same JSON object goes inside <tool_call>):\n<tool_call>\n{\n  \"name\": \"noema.web.retrieve\",\n  \"arguments\": {\n    \"query\": \"...\",\n    \"count\": 3,\n    \"safesearch\": \"moderate\"\n  }\n}\n</tool_call>\n\nRules:\n- Default to count 3; use 5 only for very diverse queries and only if needed.\n- Decide first; only call if needed.\n- Make exactly one tool call and WAIT for the result.\n- Do NOT emit tool calls inside <think> or chain-of-thought. If you include a <think> section, always close it with </think> and output any <tool_call> (or JSON tool object) only AFTER the final </think>.\n- Do NOT output tool results yourself and NEVER put results inside <tool_call>; that tag wraps the call JSON only.\n- Do NOT use code fences (```); emit only the JSON or the <tool_call> wrapper.\n- Do not mix formats; choose JSON or XML, not both.\n- After results, answer with concise citations like [1], [2]."
            t += "\n\n" + instr
        }
        return t
    }

    /// Removes any accidental anti-reasoning directives such as "/nothink" from the system prompt
    /// while preserving the intended guidance (we rely on <think> tags to contain reasoning).
    private func sanitizeSystemPrompt(_ s: String) -> String {
        var t = s
        // Remove common variants of nothink flags if present
        let patterns = ["/nothink", "\\bnothink\\b", "no-think", "no think"]
        for p in patterns {
            if let rx = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: (t as NSString).length)
                t = rx.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "")
            } else {
                t = t.replacingOccurrences(of: p, with: "", options: .caseInsensitive)
            }
        }
        // Normalize whitespace after removals
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private(set) var currentKind: ModelKind = .other
    private var usePrompt = true

    private var gemmaAutoTemplated = false
    private var runCounter = 0
    private var activeRunID = 0
    // Persist the same Leap Conversation across tool calls; no reset flags
    private var currentStreamTask: Task<Void, Never>?
    private var currentContextTask: Task<String, Never>?
    private var titleTask: Task<Void, Never>?
    private var currentContinuationTask: Task<Void, Never>?
    private var lastTitledMessageID: UUID?
    private var lastTitledHash: Int?
    private var loadedURL: URL?
    private var loadedSettings: ModelSettings?
    private var loadedFormat: ModelFormat?
    private var currentInjectedTokenOverhead: Int = 0

    /// Reference to the global model manager so the chat view model can access
    /// the currently selected dataset for RAG lookups.
    weak var modelManager: AppModelManager?
    /// Dataset manager used to track indexing status while performing
    /// retrieval or injection. Held weakly since it is owned by the
    /// main view hierarchy.
    weak var datasetManager: DatasetManager?

    private var client: AnyLLMClient?
    
    // Timer for periodic subscription status checks
    private var subscriptionCheckTimer: Timer?
    @AppStorage("defaultModelPath") private var defaultModelPath = ""
    @AppStorage("verboseLogging") private var verboseLogging = false
    @AppStorage("ragMaxChunks") private var ragMaxChunks = 5
    @AppStorage("ragMinScore") private var ragMinScore = 0.5

    private var didInjectDataset = false
    private var lastDatasetID: String?

    init() {
        suppressAutoDatasetRestore = true
        if let data = try? Data(contentsOf: Self.sessionsURL()),
           let decoded = try? JSONDecoder().decode([Session].self, from: data),
           !decoded.isEmpty {
            sessions = decoded
            activeSessionID = decoded.first?.id
        } else {
            let system = Msg(role: "system", text: systemPromptText, timestamp: Date())
            let first = Session(title: "New chat", messages: [system], date: Date())
            sessions = [first]
            activeSessionID = first.id
        }
        suppressAutoDatasetRestore = false
        // Recreate rolling thought view models for loaded sessions
        recreateRollingThoughtViewModels()
        // Ensure tools are registered early so calls are executable during the first run
        initializeToolSystem()
    }

    private static func sessionsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sessions.json")
    }

    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: Self.sessionsURL())
        }
    }

    private func applySessionDataset() {
        guard let idx = activeIndex else {
            modelManager?.setActiveDataset(nil)
            return
        }
        if let id = sessions[idx].datasetID,
           let ds = modelManager?.downloadedDatasets.first(where: { $0.datasetID == id }) {
            modelManager?.setActiveDataset(ds)
        } else {
            modelManager?.setActiveDataset(nil)
        }
    }

    func setDatasetForActiveSession(_ ds: LocalDataset?) {
        guard let idx = activeIndex else { return }
        sessions[idx].datasetID = ds?.datasetID
        modelManager?.setActiveDataset(ds)
        // Do not auto-warm embedder here; readiness will be ensured when actually used
    }

    private static func defaultTitle(date: Date = .now) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
    private var activeIndex: Int? {
        guard let id = activeSessionID else { return nil }
        return sessions.firstIndex { $0.id == id }
    }

    private var streamSessionIndex: Int?

    var streamMsgs: [Msg] {
        get {
            if let idx = streamSessionIndex, sessions.indices.contains(idx) {
                return sessions[idx].messages
            }
            return msgs
        }
        set {
            if let idx = streamSessionIndex, sessions.indices.contains(idx) {
                sessions[idx].messages = newValue
            } else {
                msgs = newValue
            }
        }
    }

    var msgs: [Msg] {
        get { activeIndex.flatMap { sessions[$0].messages } ?? [] }
        set {
            if let idx = activeIndex { sessions[idx].messages = newValue }
        }
    }

    var isStreaming: Bool { msgs.last?.streaming == true }

    var totalTokens: Int {
        let base = msgs.compactMap { $0.perf?.tokenCount }.reduce(0, +)
        var extra = 0
        // Include injected dataset token overhead
        extra += max(0, currentInjectedTokenOverhead)
        // Include system prompt tokens (fast sync estimate)
        extra += estimateTokensSync(systemPromptText)
        // Include all user prompt tokens (fast sync estimate)
        let userText = msgs.filter { $0.role == "🧑‍💻" || $0.role.lowercased() == "user" }.map { $0.text }.joined(separator: "\n")
        extra += estimateTokensSync(userText)
        // Include web/tool result tokens (reinjected into prompt as <tool_response> blocks)
        let toolText = msgs.last?.toolCalls?
            .compactMap { $0.result }
            .joined(separator: "\n") ?? ""
        extra += estimateTokensSync(toolText)
        // Include dataset RAG injected context tokens only when not already counted via full injection overhead
        if currentInjectedTokenOverhead == 0, let ctx = msgs.last?.retrievedContext, !ctx.isEmpty {
            extra += estimateTokensSync(ctx)
        }
        return base + extra
    }

    private func estimateTokensSync(_ text: String) -> Int {
        // Cheap approximation: whitespace-delimited token count
        // Avoids calling async embedding tokenizer on the main thread
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.split { $0.isWhitespace }.count
    }
    var contextLimit: Double { loadedSettings?.contextLength ?? 4096 }

    func select(_ session: Session) {
        activeSessionID = session.id
    }

    func startNewSession() {
        currentStreamTask?.cancel()
        gemmaAutoTemplated = false
        let system = Msg(role: "system", text: systemPromptText, timestamp: Date())
        let new = Session(title: "New chat", messages: [system], date: Date())
        sessions.insert(new, at: 0)
        activeSessionID = new.id
        injectionStage = .none
        injectionMethod = nil
        didInjectDataset = false
        lastDatasetID = nil
        
        // Randomize seed per session without persisting unless user set it
        if let model = modelManager?.loadedModel {
            let settings = modelManager?.settings(for: model) ?? ModelSettings.default(for: model.format)
            if modelLoaded {
                if let explicitSeed = settings.seed, explicitSeed != 0 {
                    // Respect user-provided seed
                    setenv("LLAMA_SEED", String(explicitSeed), 1)
                } else {
                    // Use a random seed for this session only (do not persist)
                    setenv("LLAMA_SEED", String(Int.random(in: 1...999_999)), 1)
                }
            }
        }
    }

    func delete(_ session: Session) {
        currentStreamTask?.cancel()
        sessions.removeAll { $0.id == session.id }
        if activeSessionID == session.id {
            activeSessionID = sessions.first?.id
        }
    }

    func toggleFavorite(_ session: Session) {
        guard let idx = sessions.firstIndex(of: session) else { return }
        sessions[idx].isFavorite.toggle()
    }

    private func ensureClient(url: URL, settings: ModelSettings?, format: ModelFormat?) async throws {
        guard client == nil else { return }
        loading = true
        stillLoading = false
        loadError = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.loading == true { self?.stillLoading = true }
        }
        defer { loading = false; stillLoading = false }

        // Restrict Metal kernels to the model's quantization only for GGUF.
        let detectedFmt = format ?? ModelFormat.detect(from: url)
        var loadURL = url
        if detectedFmt == .gguf {
            let quantLabel = QuantExtractor.shortLabel(from: url.lastPathComponent, format: .gguf).lowercased()
            if quantLabel.lowercased().starts(with: "q") {
                setenv("LLAMA_METAL_KQUANTS", quantLabel, 1)
            } else {
                setenv("LLAMA_METAL_KQUANTS", "", 1)
            }
            // Validate GGUF magic; if invalid or missing, try to re-discover under the model's base directory
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir)
            let isValid = exists && (!isDir.boolValue ? InstalledModelsStore.isValidGGUF(at: loadURL) : true)
            if !isValid || !exists {
                let base = InstalledModelsStore.baseDir(for: .gguf, modelID: modelManager?.downloadedModels.first(where: { $0.url == loadURL || $0.url.deletingLastPathComponent() == loadURL })?.modelID ?? inferRepoID(from: loadURL) ?? loadURL.deletingLastPathComponent().lastPathComponent)
                if let alt = InstalledModelsStore.firstGGUF(in: base) {
                    loadURL = alt
                }
            }
        } else {
            setenv("LLAMA_METAL_KQUANTS", "", 1)
        }

        guard FileManager.default.fileExists(atPath: loadURL.path) else {
            throw NSError(domain: "Noema", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model not downloaded"])
        }
        // For MLX, ensure we pass a directory URL (model root)
        if detectedFmt == .mlx {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir)
            if !isDir.boolValue {
                // Try parent directory
                let dir = loadURL.deletingLastPathComponent()
                var d: ObjCBool = false
                if FileManager.default.fileExists(atPath: dir.path, isDirectory: &d), d.boolValue {
                    loadURL = dir
                    if verboseLogging { print("[ChatVM] Adjusted MLX URL to directory: \(dir.path)") }
                } else {
                    throw NSError(domain: "Noema", code: 400, userInfo: [NSLocalizedDescriptionKey: "MLX model directory missing"])
                }
            }
            // Sanity check expected files
            let cfg = loadURL.appendingPathComponent("config.json")
            if !FileManager.default.fileExists(atPath: cfg.path) {
                throw NSError(domain: "Noema", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing config.json in MLX model directory"])
            }
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64 {
            let sizeGB = Double(size) / 1_073_741_824.0
            let text = DeviceRAMInfo.current().limit
            if let num = Double(text.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)),
               sizeGB > num {
                loadError = "Model may exceed available RAM (\(String(format: "%.1f", sizeGB)) GB > \(text))"
            }
        }
        // Resolve tokenizer for MLX if not provided
        var finalSettings = settings
        if detectedFmt == .mlx {
            if (finalSettings?.tokenizerPath ?? "").isEmpty {
                let possibleTokenizers = ["tokenizer.json", "tokenizer.model", "spiece.model", "sentencepiece.bpe.model"]
                let existing = possibleTokenizers
                    .map { loadURL.appendingPathComponent($0) }
                    .first { FileManager.default.fileExists(atPath: $0.path) }
                if let existing {
                    var s = finalSettings ?? ModelSettings.default(for: .mlx)
                    s.tokenizerPath = existing.path
                    finalSettings = s
                }
            }
            // Preflight validation for MLX models to surface clear errors before loading
            do {
                // Validate config.json is well-formed JSON
                let cfg = loadURL.appendingPathComponent("config.json")
                let data = try Data(contentsOf: cfg)
                _ = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw NSError(domain: "Noema", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid or missing config.json in MLX model directory"])
            }
            // Ensure a tokenizer asset is present. Accept tokenizer.json or common SentencePiece names.
            let tokJSON = loadURL.appendingPathComponent("tokenizer.json")
            let possibleTokenizers = ["tokenizer.json", "tokenizer.model", "spiece.model", "sentencepiece.bpe.model"]
            func isGitLFSPointer(_ url: URL) -> Bool {
                guard let d = try? Data(contentsOf: url), d.count < 4096,
                      let s = String(data: d, encoding: .utf8) else { return false }
                let lower = s.lowercased()
                return lower.contains("git-lfs") || lower.contains("oid sha256:")
            }
            var hasTokenizerAsset = possibleTokenizers.contains { name in
                let u = loadURL.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: u.path) {
                    if name == "tokenizer.json" && isGitLFSPointer(u) { return false }
                    return true
                }
                return false
            }
            if !hasTokenizerAsset {
                // Try to resolve repo id via store metadata
                var repoHint: String? = nil
                if let mm = modelManager {
                    if let m = mm.downloadedModels.first(where: { $0.url == loadURL || $0.url.deletingLastPathComponent() == loadURL }) {
                        repoHint = m.modelID
                    }
                }
                let repoID = repoHint ?? inferRepoID(from: loadURL)
                if let repoID {
                    if verboseLogging { print("[ChatVM] Attempting to fetch tokenizer.json for repo: \(repoID)") }
                    await fetchTokenizer(into: loadURL, repoID: repoID)
                    hasTokenizerAsset = possibleTokenizers.contains { name in
                        let u = loadURL.appendingPathComponent(name)
                        if FileManager.default.fileExists(atPath: u.path) {
                            if name == "tokenizer.json" && isGitLFSPointer(u) { return false }
                            return true
                        }
                        return false
                    }
                }
            }
            if !hasTokenizerAsset {
                throw NSError(domain: "Noema", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing tokenizer assets in MLX model directory"])
            }
            // If still missing tokenizerPath, set it now to the first available asset
            if (finalSettings?.tokenizerPath ?? "").isEmpty {
                if let first = possibleTokenizers
                    .map({ loadURL.appendingPathComponent($0) })
                    .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    var s = finalSettings ?? ModelSettings.default(for: .mlx)
                    s.tokenizerPath = first.path
                    finalSettings = s
                }
            }
            // Ensure at least one weight file exists (.safetensors or .npz)
            let contents = (try? FileManager.default.contentsOfDirectory(at: loadURL, includingPropertiesForKeys: nil)) ?? []
            let hasWeights = contents.contains { url in
                let ext = url.pathExtension.lowercased()
                return ext == "safetensors" || ext == "npz"
            }
            if !hasWeights {
                throw NSError(domain: "Noema", code: 400, userInfo: [NSLocalizedDescriptionKey: "No weight files (.safetensors or .npz) found in MLX model directory"])
            }
        }
        if let fmt = format {
            switch fmt {
            case .mlx:
                finalSettings?.gpuLayers = 0
            case .gguf:
                let layers = ModelScanner.layerCount(for: url, format: .gguf)
                let ctxMax = GGUFMetadata.contextLength(at: url) ?? Int.max
                if var s = finalSettings {
                    // Preserve sentinel (-1) meaning "all layers"; otherwise clamp to [0, layers]
                    if s.gpuLayers >= 0 {
                        s.gpuLayers = min(max(0, s.gpuLayers), max(0, layers))
                    }
                    s.contextLength = min(s.contextLength, Double(ctxMax))
                    // If a tokenizer.json exists next to the GGUF, record it so prompt
                    // detection can read DeepSeek/Qwen markers via LLAMA_TOKENIZER_PATH.
                    if (s.tokenizerPath ?? "").isEmpty {
                        var isDir: ObjCBool = false
                        var modelDir = url.deletingLastPathComponent()
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                            modelDir = url
                        }
                        let tok = modelDir.appendingPathComponent("tokenizer.json")
                        if FileManager.default.fileExists(atPath: tok.path) {
                            s.tokenizerPath = tok.path
                        }
                    }
                    finalSettings = s
                }
            case .slm:
                break
            case .apple:
                break
            }
        }
        if let s = finalSettings {
            // Apply runtime variables only for GGUF models.
            if detectedFmt == .gguf {
                applyEnvironmentVariables(from: s)
            }
            if verboseLogging { print("[ChatVM] loading \(loadURL.lastPathComponent) with context \(Int(s.contextLength))") }
        } else {
            if verboseLogging {
                let kind = detectedFmt == .gguf ? "GGUF" : (detectedFmt == .mlx ? "MLX" : "SLM")
                print("[ChatVM] loading \(kind) from \(loadURL.lastPathComponent)…")
            }
        }
        if verboseLogging { print("MODEL_LOAD_START \(Date().timeIntervalSince1970)") }


        if let f = format {
            switch f {
            case .mlx:
                print("[ChatVM] MLX load start: \(loadURL.path)")
                // Choose VLM vs Text based on model contents
                if MLXBridge.isVLMModel(at: loadURL) {
                    client = try await MLXBridge.makeVLMClient(url: loadURL)
                } else {
                    client = try await MLXBridge.makeTextClient(url: loadURL, settings: finalSettings)
                }
                loadedFormat = .mlx
            case .gguf:
                client = try await AnyLLMClient(
                    NoemaLlamaClient.llama(
                        url: loadURL,
                        parameter: .init(options: .init(extraEOSTokens: ["<|im_end|>", "<end_of_turn>"], verbose: true))
                    )
                )
                loadedFormat = .gguf
            case .slm:
                // Disarm web search before activating Leap SLM so no tools register
                SettingsStore.shared.webSearchArmed = false
                let runner = try await Leap.load(url: loadURL)
                let ident = loadURL.deletingPathExtension().lastPathComponent
                // Do not inject a system prompt for SLM models; let them run normally
                let leapClient = LeapLLMClient.make(runner: runner, modelIdentifier: ident)
                client = try await AnyLLMClient(leapClient)
                loadedFormat = .slm
                // Datasets are not supported with SLM models – clear any active selection
                if modelManager?.activeDataset != nil { setDatasetForActiveSession(nil) }
            case .apple:
                throw NSError(domain: "Noema", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unsupported model format"]) 
            }
        } else {
            // Auto-detect format and load via appropriate client
            let detected = ModelFormat.detect(from: loadURL)
            switch detected {
            case .mlx:
                print("[ChatVM] MLX load start: \(loadURL.path)")
                if MLXBridge.isVLMModel(at: loadURL) {
                    client = try await MLXBridge.makeVLMClient(url: loadURL)
                } else {
                    client = try await MLXBridge.makeTextClient(url: loadURL, settings: finalSettings)
                }
                loadedFormat = .mlx
            case .gguf:
                client = try await AnyLLMClient(
                    NoemaLlamaClient.llama(
                        url: loadURL,
                        parameter: .init(options: .init(extraEOSTokens: ["<|im_end|>", "<end_of_turn>"], verbose: true))
                    )
                )
                loadedFormat = .gguf
            case .slm:
                let runner = try await Leap.load(url: loadURL)
                let ident = loadURL.deletingPathExtension().lastPathComponent
                // Do not inject a system prompt for SLM models; let them run normally
                let leapClient = LeapLLMClient.make(runner: runner, modelIdentifier: ident)
                client = try await AnyLLMClient(leapClient)
                loadedFormat = .slm
                // Datasets are not supported with SLM models – clear any active selection
                if modelManager?.activeDataset != nil { setDatasetForActiveSession(nil) }
            case .apple:
                // Detection shouldn't return .apple for file-based models; ignore.
                break
            }
        }

        currentKind = ModelKind.detect(id: url.lastPathComponent)
        usePrompt = true
        gemmaAutoTemplated = false
        loadedURL = loadURL
        loadedSettings = finalSettings ?? ModelSettings.default(for: loadedFormat ?? .gguf)

        modelLoaded = true

        // Update image-input capability from stored metadata; fallback to local detection when unknown
        if let loadedModel = modelManager?.downloadedModels.first(where: { $0.url == loadURL }) {
            supportsImageInput = loadedModel.isMultimodal
        } else {
            supportsImageInput = false
        }
        if supportsImageInput == false {
            // Heuristic fallback by format to ensure the image button appears when applicable
            if let fmt = loadedFormat {
                switch fmt {
                case .gguf:
                    supportsImageInput = Self.guessLlamaVisionModel(from: loadURL)
                case .mlx:
                    supportsImageInput = MLXBridge.isVLMModel(at: loadURL)
                case .slm:
                    // Prefer Leap catalog slug heuristic; fallback to bundle scan when available
                    let slug = loadURL.deletingPathExtension().lastPathComponent
                    supportsImageInput = LeapCatalogService.isVisionQuantizationSlug(slug) || LeapCatalogService.bundleLikelyVision(at: loadURL)
                case .apple:
                    break
                }
                // Persist capability if newly detected
                if supportsImageInput, let manager = modelManager,
                   let model = manager.downloadedModels.first(where: { $0.url == loadURL }) {
                    manager.setCapabilities(modelID: model.modelID, quant: model.quant, isMultimodal: true, isToolCapable: model.isToolCapable)
                }
            }
        }

        // Persist current model format and function-calling capability for tool gating (e.g., web search)
        do {
            let d = UserDefaults.standard
            if let fmt = loadedFormat { d.set(fmt.rawValue, forKey: "currentModelFormat") }
            var supportsToolCalls = false
            if let manager = modelManager, let u = loadedURL, let m = manager.downloadedModels.first(where: { $0.url == u }) {
                supportsToolCalls = m.isToolCapable
                if supportsToolCalls == false {
                    let heuristic = await ToolCapabilityDetector.isToolCapableCachedOrHeuristic(repoId: m.modelID)
                    supportsToolCalls = heuristic
                }
            }
            if loadedFormat == .slm {
                supportsToolCalls = false
                // Force-disarm web search while Leap SLM is active
                SettingsStore.shared.webSearchArmed = false
            }
            d.set(supportsToolCalls, forKey: "currentModelSupportsFunctionCalling")
        }

        if verboseLogging { print("MODEL_LOAD_READY \(Date().timeIntervalSince1970)") }
        if verboseLogging { print("[ChatVM] client ready ✅") }
        if loadedFormat == .mlx { print("[ChatVM] MLX client ready ✅") }

        // Persist the effective settings actually used for this load,
        // so next time we restore the exact last-used configuration.
        if let manager = modelManager,
           let u = loadedURL,
           let s = loadedSettings,
           let m = manager.downloadedModels.first(where: { $0.url == u }) {
            manager.updateSettings(s, for: m)
        }
    }

    func applyEnvironmentVariables(from s: ModelSettings) {
        setenv("LLAMA_CONTEXT_SIZE", String(Int(s.contextLength)), 1)
        // If sentinel (-1): request all available GPU layers by using a large value (clamped by backend)
        let nGpu = s.gpuLayers < 0 ? 1_000_000 : s.gpuLayers
        setenv("LLAMA_N_GPU_LAYERS", String(nGpu), 1)
        setenv("LLAMA_THREADS", String(s.cpuThreads), 1)
        setenv("LLAMA_KV_OFFLOAD", s.kvCacheOffload ? "1" : "0", 1)
        setenv("LLAMA_MMAP", s.useMmap ? "1" : "0", 1)
        setenv("LLAMA_KEEP", s.keepInMemory ? "1" : "0", 1)
        if let seed = s.seed {
            setenv("LLAMA_SEED", String(seed), 1)
        } else {
            // Do not set a persistent seed here; session start will set a random seed per session
            unsetenv("LLAMA_SEED")
        }
        // Flash Attention toggle removed; rely on backend defaults
        setenv("LLAMA_K_QUANT", s.kCacheQuant.rawValue, 1)
        // V-cache quantization is disabled; ensure env is unset so backends default to F16
        unsetenv("LLAMA_V_QUANT")
        if let tok = s.tokenizerPath { setenv("LLAMA_TOKENIZER_PATH", tok, 1) }
    }

    func load(url: URL, settings: ModelSettings? = nil, format: ModelFormat? = nil) async -> Bool {
        var fmt = format
        if fmt == nil {
            fmt = ModelFormat.detect(from: url)
        }
        
        // Set the loading model name for the notification
        let modelName = url.deletingPathExtension().lastPathComponent
        await MainActor.run {
            modelManager?.loadingModelName = modelName
        }

        do {
            try await ensureClient(url: url, settings: settings, format: fmt)
            loadedFormat = fmt
            if let s = settings { self.promptTemplate = s.promptTemplate }

            // Clear the loading model name on success
            await MainActor.run {
                modelManager?.loadingModelName = nil
            }

            return true
        } catch {
            // Surface the error to the UI so the user knows what failed.
            loadError = error.localizedDescription
            if verboseLogging { print("[ChatVM] ❌ \(error.localizedDescription)") }

            // Clear the loading model name on failure
            await MainActor.run {
                modelManager?.loadingModelName = nil
            }

            return false
        }
    }

    private func unloadResources() {
        // Ensure all async work stops before releasing the client to avoid leaks.
        currentContextTask?.cancel()
        currentContextTask = nil
        currentStreamTask?.cancel()
        currentStreamTask = nil
        titleTask?.cancel()
        titleTask = nil

        // Preserve rolling thought boxes across unloads. Finish any in-flight streams
        // so boxes transition to a completed state, and persist their state.
        for viewModel in rollingThoughtViewModels.values {
            if viewModel.phase != .complete { viewModel.finish() }
        }
        do {
            let keys = Array(rollingThoughtViewModels.keys)
            UserDefaults.standard.set(keys, forKey: "RollingThought.Keys")
            for (key, vm) in rollingThoughtViewModels {
                vm.saveState(forKey: "RollingThought." + key)
            }
        }

        client?.unload()
        client = nil
        modelLoaded = false
        loadedURL = nil
        loadedSettings = nil
        loadedFormat = nil
    }

    nonisolated func unload() async {
        await MainActor.run { self.unloadResources() }
    }

    @preconcurrency
    func activate(runner: any ModelRunner, url: URL) {
        unloadResources()
        do {
            let ident = url.deletingPathExtension().lastPathComponent
            client = try AnyLLMClient(LeapLLMClient.make(runner: runner, modelIdentifier: ident))
            loadedFormat = .slm
            loadedSettings = ModelSettings.default(for: .slm)
            loadedURL = url
            modelLoaded = true
        } catch {
            client = nil
            modelLoaded = false
        }
    }


    func stop() {
        // Proactively cancel backend generation (llama.cpp) and any in-flight tool calls
        client?.cancelActive()
        currentContextTask?.cancel()
        currentContextTask = nil
        currentStreamTask?.cancel()
        currentStreamTask = nil
        currentContinuationTask?.cancel()
        currentContinuationTask = nil
        titleTask?.cancel()
        titleTask = nil
        
        // Do not remove rolling thought boxes when stopping; finish and persist them instead
        for viewModel in rollingThoughtViewModels.values {
            if viewModel.phase != .complete { viewModel.finish() }
        }
        do {
            let keys = Array(rollingThoughtViewModels.keys)
            UserDefaults.standard.set(keys, forKey: "RollingThought.Keys")
            for (key, vm) in rollingThoughtViewModels {
                vm.saveState(forKey: "RollingThought." + key)
            }
        }
        
        if msgs.last?.streaming == true {
            var m = msgs
            let idx = m.index(before: m.endIndex)
            m[idx].streaming = false
            msgs = m
        }
        injectionStage = .none
        injectionMethod = nil
        streamSessionIndex = nil
    }

    private func resetSession() async {
        currentContextTask?.cancel()
        currentContextTask = nil
        currentStreamTask?.cancel()
        currentStreamTask = nil
        titleTask?.cancel()
        titleTask = nil
        client = nil
        modelLoaded = false
        guard let url = loadedURL else { return }
        try? await ensureClient(url: url, settings: loadedSettings, format: loadedFormat)
        streamSessionIndex = nil
    }
    
    /// Check subscription status to prevent infinite usage
    private func checkSubscriptionStatus() async {
        await RevenueCatManager.shared.refreshEntitlements()
        
        if verboseLogging {
            let hasUnlimited = SettingsStore.shared.hasUnlimitedSearches
            print("[ChatVM] Subscription check - hasUnlimitedSearches: \(hasUnlimited)")
        }
    }
    
    /// Start periodic subscription status checking
    func startSubscriptionCheckTimer() {
        // Check subscription status every 5 minutes
        subscriptionCheckTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkSubscriptionStatus()
            }
        }
    }
    
    /// Stop periodic subscription status checking
    private func stopSubscriptionCheckTimer() {
        subscriptionCheckTimer?.invalidate()
        subscriptionCheckTimer = nil
    }

    private func appendUser(_ text: String, purpose: RunPurpose) {
        precondition(purpose == .chat, "appendUser used for non-chat run")
        var m = msgs
        m.append(.init(role: "🧑‍💻", text: text, timestamp: Date()))
        msgs = m
    }

    private func appendAssistantPlaceholder(purpose: RunPurpose) -> Int {
        precondition(purpose == .chat, "appendAssistant used for non-chat run")
        var m = msgs
        m.append(.init(role: "🤖", text: "", timestamp: Date(), streaming: true))
        msgs = m
        return msgs.index(before: msgs.endIndex)
    }

    // UI callback (legacy) – forwards to sendMessage with captured prompt
    func send() async {
        await sendMessage(prompt)
    }

    /// New send variant that avoids races with UI clearing the prompt by accepting the text explicitly.
    func sendMessage(_ rawInput: String) async {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        
        // Check subscription status on every message to prevent infinite usage
        await checkSubscriptionStatus()
        
        prompt = ""

        if verboseLogging { print("[ChatVM] USER ▶︎ \(input)") }
        Task { await logger.log("[ChatVM] USER ▶︎ \(input)") }

        titleTask?.cancel()
        titleTask = nil

        currentStreamTask?.cancel()
        runCounter += 1
        let myID = runCounter
        activeRunID = myID

        guard let sIdx = self.activeIndex else { return }
        streamSessionIndex = sIdx
        var didLaunchStreamTask = false
        defer {
            if !didLaunchStreamTask { streamSessionIndex = nil }
        }
        var m = self.streamMsgs
        m.append(.init(role: "🧑‍💻", text: input, timestamp: Date()))
        self.streamMsgs = m
        let attachments = pendingImageURLs.map { $0.path }
        if !attachments.isEmpty {
            m = self.streamMsgs
            let idx = m.index(before: m.endIndex)
            m[idx].imagePaths = attachments
            self.streamMsgs = m
        }
        m = self.streamMsgs
        m.append(.init(role: "🤖", text: "", timestamp: Date(), streaming: true))
        self.streamMsgs = m
        let outIdx = self.streamMsgs.index(before: self.streamMsgs.endIndex)
        let history = self.streamMsgs

        // Use local backends only.

        var promptStr: String
        let stops: [String]
        let maxTokens: Int
        var llmInput: LLMInput
        if loadedFormat == .slm {
            promptStr = input
            stops = []
            maxTokens = Int(self.contextLimit * 0.9)
            let userMessage = ChatMessage(role: "user", content: input)
            llmInput = LLMInput(.messages([userMessage]))
        } else {
            let (basePrompt, s, maxT) = self.buildPrompt(kind: currentKind, history: history)
            promptStr = basePrompt
            stops = s
            maxTokens = maxT
            llmInput = LLMInput(.plain("") ) // will assign after final prompt computed
        }
        // Log prompt summary to the app log for diagnostics
        do {
            let previewLimit = 500
            let preview = promptStr.count > previewLimit ? String(promptStr.prefix(previewLimit)) + "… [truncated]" : promptStr
            Task { await logger.log("[ChatVM] Prompt built len=\(promptStr.count) stops=\(stops.count) maxTokens=\(maxTokens)\n\(preview)") }
        }

        // If a dataset is active decide whether to inject the full content or
        // fall back to RAG lookups and prepend the resulting context to the
        // prompt before sending it to the model.
        // Disallow dataset usage with SLM models
        let datasetAllowed = (loadedFormat != .some(.slm))
        if datasetAllowed, let ds = modelManager?.activeDataset, ds.isIndexed {
            // Ensure embedder only when retrieval is actually needed
            // Strict on-demand: do not trigger any download from chat path
            await EmbeddingModel.shared.ensureModel()
            if !(await EmbeddingModel.shared.isReady()) {
                await EmbeddingModel.shared.warmUp()
            }
            if verboseLogging { print("[ChatVM] Embed ready: \(await EmbeddingModel.shared.isReady())") }
            injectionStage = .deciding
            injectionMethod = nil
            if ds.datasetID != lastDatasetID {
                lastDatasetID = ds.datasetID
                didInjectDataset = false
            }
            currentContextTask = Task { [weak self] in
                guard let self else { return "" }
                var ctx = ""
                if !self.didInjectDataset {
                    let estimate = await DatasetRetriever.shared.estimateTokens(in: ds)
                    if Task.isCancelled { return "" }
                    let embedReady = await EmbeddingModel.shared.isReady()
                    if Double(estimate) <= self.contextLimit * 0.6 && embedReady {
                        await MainActor.run {
                            self.injectionMethod = .full
                            self.injectionStage = .decided
                        }
                        ctx = await DatasetRetriever.shared.fetchAllContent(for: ds)
                        // Precompute token overhead for full injection so we can reflect it in UI stats.
                        self.currentInjectedTokenOverhead = await EmbeddingModel.shared.countTokens(ctx)
                         // Even with full-content injection, compute top citations for UI transparency
                         // without altering the injected context.
                         let preview = await DatasetRetriever.shared.fetchContextDetailed(
                             for: input,
                             dataset: ds,
                             maxChunks: min(3, self.ragMaxChunks),
                             minScore: Float(self.ragMinScore)
                         ) { status in
                             Task { @MainActor in
                                 self.datasetManager?.processingStatus[ds.datasetID] = status
                                 if let dc = self.datasetManager?.downloadController {
                                     dc.showOverlay = status.stage != .completed && status.stage != .failed
                                 }
                             }
                         }
                         await MainActor.run {
                             self.streamMsgs[outIdx].citations = preview.map { ChatVM.Msg.Citation(text: $0.text, source: $0.source) }
                         }
                        // Safety check: if full content is too large after exact count, fall back to RAG
                        if Double(self.currentInjectedTokenOverhead) > self.contextLimit * 0.6 {
                            await MainActor.run {
                                self.injectionMethod = .rag
                                self.injectionStage = .processing
                            }
                            let detailed = await DatasetRetriever.shared.fetchContextDetailed(
                                for: input,
                                dataset: ds,
                                maxChunks: self.ragMaxChunks,
                                minScore: Float(self.ragMinScore)
                            ) { status in
                                Task { @MainActor in
                                    self.datasetManager?.processingStatus[ds.datasetID] = status
                                    if let dc = self.datasetManager?.downloadController {
                                        dc.showOverlay = status.stage != .completed && status.stage != .failed
                                    }
                                }
                            }
                            ctx = detailed.enumerated().map { "[\($0.offset + 1)] \($0.element.text)" }.joined(separator: "\n\n")
                            await MainActor.run {
                                self.streamMsgs[outIdx].citations = detailed.map { ChatVM.Msg.Citation(text: $0.text, source: $0.source) }
                            }
                            self.currentInjectedTokenOverhead = 0
                        }
                    } else {
                        await MainActor.run {
                            self.injectionMethod = .rag
                            self.injectionStage = .processing
                        }
                        let detailed = await DatasetRetriever.shared.fetchContextDetailed(
                            for: input,
                            dataset: ds,
                            maxChunks: self.ragMaxChunks,
                            minScore: Float(self.ragMinScore)
                        ) { status in
                            Task { @MainActor in
                                self.datasetManager?.processingStatus[ds.datasetID] = status
                                if let dc = self.datasetManager?.downloadController {
                                    dc.showOverlay = status.stage != .completed && status.stage != .failed
                                }
                            }
                        }
                        ctx = detailed.enumerated().map { "[\($0.offset + 1)] \($0.element.text)" }.joined(separator: "\n\n")
                        await MainActor.run {
                            self.streamMsgs[outIdx].citations = detailed.map { ChatVM.Msg.Citation(text: $0.text, source: $0.source) }
                        }
                        self.currentInjectedTokenOverhead = 0
                    }
                    self.didInjectDataset = true
                } else {
                    await MainActor.run {
                        self.injectionMethod = .rag
                        self.injectionStage = .processing
                    }
                    let detailed = await DatasetRetriever.shared.fetchContextDetailed(
                        for: input,
                        dataset: ds,
                        maxChunks: self.ragMaxChunks,
                        minScore: Float(self.ragMinScore)
                    ) { status in
                        Task { @MainActor in
                            self.datasetManager?.processingStatus[ds.datasetID] = status
                            if let dc = self.datasetManager?.downloadController {
                                dc.showOverlay = status.stage != .completed && status.stage != .failed
                            }
                        }
                    }
                    ctx = detailed.enumerated().map { "[\($0.offset + 1)] \($0.element.text)" }.joined(separator: "\n\n")
                    await MainActor.run {
                        self.streamMsgs[outIdx].citations = detailed.map { ChatVM.Msg.Citation(text: $0.text, source: $0.source) }
                    }
                    self.currentInjectedTokenOverhead = 0
                }
                return ctx
            }
            let ctx = await currentContextTask?.value ?? ""
            currentContextTask = nil
            if !ctx.isEmpty {
                self.streamMsgs[outIdx].retrievedContext = ctx
                // Protect the prompt from pathological context sizes (token-aware)
                let maxContextTokens = Int(self.contextLimit * 0.5)
                var safeCtx = ctx
                if await EmbeddingModel.shared.countTokens(safeCtx) > maxContextTokens {
                    // Binary search the largest prefix that fits within token budget
                    var low = 0
                    var high = safeCtx.count
                    var best = 0
                    while low <= high {
                        let mid = (low + high) / 2
                        let prefix = String(safeCtx.prefix(mid))
                        let tok = await EmbeddingModel.shared.countTokens(prefix)
                        if tok <= maxContextTokens {
                            best = mid
                            low = mid + 1
                        } else {
                            high = mid - 1
                        }
                    }
                    safeCtx = String(safeCtx.prefix(best))
                }
                // Reflect the actually injected context for UI and token counting
                self.streamMsgs[outIdx].retrievedContext = safeCtx
                // Inject context inside the user section of the template to avoid breaking control tokens
                promptStr = injectContextIntoPrompt(original: promptStr, context: safeCtx, kind: self.currentKind)
                if verboseLogging {
                    print("[ChatVM] Retrieved context (\(safeCtx.count) chars): \(safeCtx.prefix(200))...")
                }
                // Keep banner visible while streaming; show "Processing" while retrieving
                injectionStage = .processing
            }
            if client == nil, let url = loadedURL {
                try? await ensureClient(url: url, settings: loadedSettings, format: loadedFormat)
            }
        } else {
            injectionStage = .none
            injectionMethod = nil
            didInjectDataset = false
            lastDatasetID = nil
            currentInjectedTokenOverhead = 0
        }

        // Log only a truncated prompt preview to avoid dumping entire documents into the console.
        let promptPreviewLimit = 1000
        let promptPreview = promptStr.count > promptPreviewLimit ? String(promptStr.prefix(promptPreviewLimit)) + "… [truncated]" : promptStr
        Task { await logger.log("[Prompt] \(promptPreview)") }
        if injectionStage != .none {
            let methodStr: String = {
                if didInjectDataset { return "dataset" }
                switch injectionMethod {
                case .some(.full): return "full"
                case .some(.rag):  return "rag"
                case .none:        return "unknown"
                }
            }()
            Task { await logger.log("[Prompt][RAG] Context injected: \(methodStr) · size=\(promptPreview.count) preview=\(promptPreview.prefix(200))…") }
        } else {
            Task { await logger.log("[Prompt][RAG] No context injected") }
        }
        Task { await logger.log("[Params] maxTokens: \(maxTokens), stops: \(stops)") }

        didLaunchStreamTask = true
        currentStreamTask = Task { [weak self, sessionIndex = sIdx] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    if self.currentContinuationTask == nil && self.streamSessionIndex == sessionIndex {
                        self.streamSessionIndex = nil
                    }
                }
            }
            // Give Leap SLM a brief moment after any cancellation to avoid
            // triggering an immediate prefill race on the next turn.
            if self.loadedFormat == .slm {
                try? await Task.sleep(nanoseconds: 80_000_000) // ~80ms
            }
            guard self.modelLoaded, let c = self.client else { return }
            let start = Date()
            var firstTok: Date?
            var count = 0
            var raw = ""
            var didProcessEmbeddedToolCall = false
            var pendingToolJSON: String? = nil
            var pendingAssistantText: String? = nil
            // Some backends (notably certain MLX ChatSession streams) yield cumulative
            // chunks instead of true deltas. To prevent visible duplication, compute
            // the non-overlapping delta to append against the text accumulated so far.
            func nonOverlappingDelta(newChunk: String, existing: String) -> String {
                if newChunk.isEmpty { return "" }
                if existing.isEmpty { return newChunk }
                // If the new chunk already contains the existing text as a prefix,
                // only take the suffix beyond it.
                if newChunk.hasPrefix(existing) {
                    return String(newChunk.dropFirst(existing.count))
                }
                // If the new chunk is exactly the current suffix, skip it. Do NOT
                // skip merely because it appears somewhere earlier in the text;
                // that would incorrectly drop legitimate tokens like "to" or ",".
                if existing.hasSuffix(newChunk) { return "" }
                // Otherwise, find the longest suffix of existing that matches the
                // prefix of newChunk and append only the remainder.
                let maxOverlap = min(existing.count, newChunk.count)
                var k = maxOverlap
                while k > 0 {
                    if existing.suffix(k) == newChunk.prefix(k) { break }
                    k -= 1
                }
                return String(newChunk.dropFirst(k))
            }
            // Seed a visible <think> box for DeepSeek prompts that open a think section in the prompt
            if self.currentKind == .deepseek && promptStr.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("<think>") {
                raw = "<think>"
                await MainActor.run {
                    if self.streamMsgs.indices.contains(outIdx) {
                        self.streamMsgs[outIdx].text = raw
                    }
                }
                await self.handleRollingThoughts(raw: raw, messageIndex: outIdx)
            }

            do {
                // Build stop sequences. Avoid adding "Step N:" stops for CoT/SLM models to not truncate reasoning-only streams.
                let isCotTemplate = (self.promptTemplate?.contains("<think>") == true)
                let defaultStopsBase = ["</s>", "<|im_end|>", "<|eot_id|>", "<end_of_turn>", "<eos>", "<｜User｜>", "<|User|>"]
                let defaultStops: [String] = {
                    if isCotTemplate || self.loadedFormat == .slm || (self.modelManager?.activeDataset != nil) { return defaultStopsBase }
                    return defaultStopsBase + ["Step 1:", "Step 2:"]
                }()
                let stopSeqs = stops.isEmpty ? defaultStops : stops
                let imagePaths = pendingImageURLs.map { $0.path }
                let useImages = self.supportsImageInput && !imagePaths.isEmpty && (self.loadedFormat == .mlx || self.loadedFormat == .gguf || self.loadedFormat == .slm)
                // If images are present and supported, inject image placeholders only for llama.cpp or MLX templates
                // For Leap SLM, do NOT inject placeholders; send raw text plus image binaries via multimodal
                let finalPrompt = promptStr
                if self.loadedFormat != .slm {
                    llmInput = useImages ? LLMInput.multimodal(text: finalPrompt, imagePaths: imagePaths)
                                          : LLMInput(.plain(finalPrompt))
                }
                // Emit a start log for this generation
                Task { await logger.log("[ChatVM] ▶︎ Starting generation (format=\(String(describing: self.loadedFormat)), kind=\(self.currentKind), images=\(useImages ? imagePaths.count : 0))") }
                // Flip to Predicting when first token arrives
                var shouldRestartWithToolResult = false
                for try await tok in try await c.textStream(from: llmInput) {
                    let trimmedTok = tok.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Handle in-band tool calls emitted as tokens
                    if trimmedTok.hasPrefix("TOOL_CALL:") {
                        // Skip tool calls that occur inside <think> chain-of-thought
                        let inThink: Bool = {
                            if let open = raw.range(of: "<think>", options: .backwards) {
                                if let close = raw.range(of: "</think>", options: .backwards) { return open.lowerBound > close.lowerBound }
                                return true
                            }
                            return false
                        }()
                        if inThink { continue }
                        if let (handled, trailing) = await interceptToolCallIfPresent(trimmedTok, messageIndex: outIdx, chatVM: self) {
                            await MainActor.run {
                                // surface a minimal hint in the message for UI callout + stream the result token
                                if self.streamMsgs.indices.contains(outIdx) { self.streamMsgs[outIdx].usedWebSearch = true }
                            }
                            // Preserve the assistant text prior to the tool call so we can
                            // reinject it when continuing after tool execution.
                            pendingAssistantText = raw
                            // Append only TOOL_RESULT marker to avoid rendering duplicate tool boxes.
                            // The UI derives a single inline ToolCallView from the result token.
                            let inlineTokens = handled + "\n"
                            raw += inlineTokens
                            await MainActor.run {
                                if self.streamMsgs.indices.contains(outIdx) {
                                    self.streamMsgs[outIdx].text.append(contentsOf: inlineTokens)
                                }
                            }
                            if let trailing, !trailing.isEmpty {
                                raw += trailing
                                await MainActor.run {
                                    if self.streamMsgs.indices.contains(outIdx) {
                                        self.streamMsgs[outIdx].text.append(contentsOf: trailing)
                                    }
                                }
                            }
                            // Capture tool result and restart generation with it injected
                            let json = handled.replacingOccurrences(of: "TOOL_RESULT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            pendingToolJSON = json
                            didProcessEmbeddedToolCall = true
                            shouldRestartWithToolResult = true
                            c.cancelActive()
                            break
                        }
                    }
                    if Task.isCancelled { break }
                    // Intercept tool-calls emitted by the model and surface UI hints
                    if trimmedTok.hasPrefix("TOOL_RESULT:") || trimmedTok.hasPrefix("TOOL_CALL:") {
                        if trimmedTok.hasPrefix("TOOL_RESULT:") {
                            let json = trimmedTok.replacingOccurrences(of: "TOOL_RESULT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { await logger.log("[Tool][Stream] TOOL_RESULT raw: \(json)") }
                            if let data = json.data(using: .utf8) {
                                // Decode Brave-style [WebHit] from new proxy format
                                struct SimpleWebHit: Decodable { let title: String; let url: String; let snippet: String }
                                if let hits = try? JSONDecoder().decode([SimpleWebHit].self, from: data) {
                                    await MainActor.run {
                                        if self.streamMsgs.indices.contains(outIdx) {
                                            self.streamMsgs[outIdx].usedWebSearch = true
                                            self.streamMsgs[outIdx].webError = nil
                                            self.streamMsgs[outIdx].webHits = hits.enumerated().map { (i, h) in
                                                .init(id: String(i+1), title: h.title, snippet: h.snippet, url: h.url, engine: "brave", score: 0)
                                            }
                                        }
                                    }
                                } else if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    // Fallback: generic error payloads {"error":..} or {"code":..,"message":..}
                                    let err: String? = {
                                        if let e = any["error"] as? String { return e }
                                        if let msg = any["message"] as? String { return msg }
                                        if let code = any["code"] { return "Error: \(code)" }
                                        return nil
                                    }()
                                    if let err = err, !err.isEmpty {
                                        await MainActor.run {
                                            if self.streamMsgs.indices.contains(outIdx) {
                                                self.streamMsgs[outIdx].usedWebSearch = true
                                                self.streamMsgs[outIdx].webError = err
                                                self.streamMsgs[outIdx].webHits = nil
                                            }
                                        }
                                    }
                                }
                            }
                            // Store the tool result and restart to continue the thought even on error
                            pendingAssistantText = raw
                            pendingToolJSON = json
                            shouldRestartWithToolResult = true
                            c.cancelActive()
                            break
                        } else if trimmedTok.hasPrefix("TOOL_CALL:") {
                            Task { await logger.log("[Tool][Stream] TOOL_CALL token: \(trimmedTok)") }
                            await MainActor.run {
                                if self.streamMsgs.indices.contains(outIdx) {
                                    self.streamMsgs[outIdx].usedWebSearch = true
                                }
                            }
                        }
                    }
                    if firstTok == nil {
                        firstTok = Date()
                        await MainActor.run { if self.injectionStage != .none { self.injectionStage = .predicting } }
                        if self.currentKind == .gemma && !self.gemmaAutoTemplated {
                            let t = trimmedTok
                            if !t.hasPrefix("<|") { self.gemmaAutoTemplated = true }
                        }
                        // Keep the decision banner visible until streaming completes to improve UX feedback
                        Task { await logger.log("[ChatVM] First token received") }
                    }
                    count += 1
                    let appendChunk = nonOverlappingDelta(newChunk: tok, existing: raw)
                    raw += appendChunk
                    
                    // Handle rolling thoughts for <think> tags
                    if !appendChunk.isEmpty {
                        await handleRollingThoughts(raw: raw, messageIndex: outIdx)
                    }
                    
                    // Check for embedded <tool_call>…</tool_call> or bare JSON tool call once per call
                    if !didProcessEmbeddedToolCall {
                        if let (handled, cleaned) = await interceptEmbeddedToolCallIfPresent(in: raw, messageIndex: outIdx, chatVM: self) {
                            Task { await logger.log("[Tool][ChatVM] Embedded tool call detected and dispatched") }
                            // Preserve assistant text prior to tool result injection for prompt rebuilding
                            pendingAssistantText = cleaned
                            // Mirror llama.cpp behaviour: append a TOOL_RESULT marker so the UI shows a tool call box
                            let inlineTokens = handled + "\n"
                            raw = cleaned + inlineTokens
                            await MainActor.run {
                                if self.streamMsgs.indices.contains(outIdx) {
                                    self.streamMsgs[outIdx].usedWebSearch = true
                                    self.streamMsgs[outIdx].text = cleaned + inlineTokens
                                }
                            }
                            let json = handled.replacingOccurrences(of: "TOOL_RESULT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            pendingToolJSON = json
                            didProcessEmbeddedToolCall = true
                            shouldRestartWithToolResult = true
                            c.cancelActive()
                            Task { await logger.log("[Tool][ChatVM] Generation cancelled to resume after tool result") }
                            break
                        }
                    }
                    // Let the model run freely; rely on backend context limits
                    if self.currentKind == .gemma && !self.gemmaAutoTemplated, let r = raw.range(of: "<|im_end|>") {
                        raw = String(raw[..<r.lowerBound])
                        break
                    }
                    // Enforce stop sequences for all backends (including MLX) using suffix check.
                    // Do not apply stop if we are inside an open <think>…</think> block, so CoT isn't cut off.
                    if let sfx = stopSeqs.first(where: { raw.hasSuffix($0) }) {
                        let lastOpen = raw.range(of: "<think>", options: .backwards)
                        let lastClose = raw.range(of: "</think>", options: .backwards)
                        let insideThink = {
                            if let o = lastOpen {
                                if let c = lastClose { return o.lowerBound > c.lowerBound }
                                return true
                            }
                            return false
                        }()
                        if !insideThink {
                            raw = String(raw.dropLast(sfx.count))
                            break
                        }
                    }
                    await MainActor.run {
                        guard myID == self.activeRunID,
                              self.streamMsgs.indices.contains(outIdx),
                              self.streamMsgs[outIdx].streaming else { return }
                        // Append tokens to the bubble to ensure top-to-bottom growth without reordering
                        self.streamMsgs[outIdx].text.append(contentsOf: appendChunk)
                    }
                    if shouldRestartWithToolResult { break }
                }
            } catch {
                await MainActor.run {
                    guard myID == self.activeRunID,
                          self.streamMsgs.indices.contains(outIdx) else { return }
                    self.streamMsgs[outIdx].streaming = false
                    if (error as? CancellationError) == nil {
                        let lower = error.localizedDescription.lowercased()
                        if !lower.contains("decode") {
                            self.streamMsgs[outIdx].text = "⚠️ " + error.localizedDescription
                        }
                    }
                }
                return
            }
            // Final safety net: if the model emitted a <tool_call> or bare JSON tool call
            // right at the end of the stream and we didn't process it mid-stream, detect
            // and dispatch it now so the conversation reliably continues.
            if !didProcessEmbeddedToolCall, pendingToolJSON == nil {
                if let (handled, cleaned) = await interceptEmbeddedToolCallIfPresent(in: raw, messageIndex: outIdx, chatVM: self) {
                    Task { await logger.log("[Tool][ChatVM] Post-stream embedded tool call detected and dispatched") }
                    // Preserve assistant text prior to the tool call
                    pendingAssistantText = cleaned
                    // Mirror llama.cpp behaviour: append a TOOL_RESULT marker so the UI shows a tool call box
                    let inlineTokens = handled + "\n"
                    raw = cleaned + inlineTokens
                    await MainActor.run {
                        if self.streamMsgs.indices.contains(outIdx) {
                            self.streamMsgs[outIdx].usedWebSearch = true
                            self.streamMsgs[outIdx].text = cleaned + inlineTokens
                        }
                    }
                    let json = handled.replacingOccurrences(of: "TOOL_RESULT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    pendingToolJSON = json
                    didProcessEmbeddedToolCall = true
                }
            }

            // Do not hide or alter chain-of-thought: preserve full model output including <think> sections.
            // Avoid transforming enumerations (e.g., "Step 1:") to keep original thinking intact.
            let cleaned = self.cleanOutput(raw, kind: self.currentKind)
            await MainActor.run {
                guard myID == self.activeRunID,
                      self.streamMsgs.indices.contains(outIdx) else { return }
                // If a tool call was detected and we're about to restart with the tool result,
                // avoid showing a transient "(no output)" placeholder which looks like a stall.
                if cleaned.isEmpty, pendingToolJSON != nil {
                    self.streamMsgs[outIdx].text = ""
                } else {
                    self.streamMsgs[outIdx].text = cleaned.isEmpty ? "(no output)" : cleaned
                }
                self.streamMsgs[outIdx].streaming = false
                if let firstTok {
                    let dur = Date().timeIntervalSince(firstTok)
                    let rate = dur > 0 ? Double(count)/dur : 0
                    let firstDelay = firstTok.timeIntervalSince(start)
                    var totalCount = count
                    if self.injectionMethod == .full && self.currentInjectedTokenOverhead > 0 {
                        totalCount += self.currentInjectedTokenOverhead
                    }
                    self.streamMsgs[outIdx].perf = .init(tokenCount: totalCount, avgTokPerSec: rate, timeToFirst: firstDelay)
                }
                if self.verboseLogging { print("[ChatVM] BOT ✓ \(self.streamMsgs[outIdx].text.prefix(80))…") }
                let ttfbStr: String = {
                    if let firstTok { return String(format: "%.2fs", firstTok.timeIntervalSince(start)) }
                    return "n/a"
                }()
                Task { await logger.log("[ChatVM] BOT ✓ tokens=\(count) ttfb=\(ttfbStr) preview=\(self.streamMsgs[outIdx].text.prefix(120))…") }
                // Clear the injection banner a bit after streaming is complete
                let clearDelay: TimeInterval = 2.0
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(clearDelay * 1_000_000_000))
                    if myID == self.activeRunID {
                        self.injectionStage = .none // Predicting done
                        self.injectionMethod = nil
                    }
                }
            }
            // Set session title from first user query with a sensible word cap
            if let sIdx = self.streamSessionIndex,
               self.sessions.indices.contains(sIdx),
               self.sessions[sIdx].title.isEmpty || self.sessions[sIdx].title == "New chat" {
                let normalized = input
                    .replacingOccurrences(of: "[\n\r]+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Remove surrounding quotes if present
                let unquoted: String = {
                    if normalized.hasPrefix("\"") && normalized.hasSuffix("\"") && normalized.count > 2 {
                        return String(normalized.dropFirst().dropLast())
                    }
                    if normalized.hasPrefix("'") && normalized.hasSuffix("'") && normalized.count > 2 {
                        return String(normalized.dropFirst().dropLast())
                    }
                    return normalized
                }()
                // Limit to a sensible word count (e.g., 8 words)
                let words = unquoted.split { $0.isWhitespace }
                let capped = words.prefix(8).joined(separator: " ")
                let cleaned = capped.trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
                self.sessions[sIdx].title = cleaned.isEmpty ? Self.defaultTitle(date: Date()) : cleaned
            }
            // If a tool was called mid-stream
            if let toolJSON = pendingToolJSON {
                // For Leap SLM models: do NOT append any visible user message.
                // We'll continue by sending a hidden user nudge (not shown in UI) so the
                // assistant continues streaming into the same bubble.
                if self.loadedFormat == .slm {
                    // Fall through to continuation task, which will stream the assistant's
                    // reply into the SAME assistant box (outIdx) using a hidden postToolInput.
                }
                // Non-SLM: continue in place with hidden tool context
                self.currentContinuationTask = Task { [weak self, pendingAssistantText, sessionIndex = sIdx] in
                    guard let self else { return }
                    defer {
                        Task { @MainActor in
                            if self.streamSessionIndex == sessionIndex {
                                self.streamSessionIndex = nil
                            }
                        }
                    }
                    guard let client = self.client else { return }
                    // REMOVED: Do not reset the client. The Leap conversation is stateful and requires prior context.
                    var pendingAssistantText = pendingAssistantText
                    
                    // Create a continuation prompt that includes the tool response context
                    // Build the current conversation with the tool result injected
                    var continuationHistory = history
                    if continuationHistory.indices.contains(outIdx) {
                        continuationHistory[outIdx].text = pendingAssistantText ?? ""
                    }
                    // Add the tool response as a hidden tool-role message so continuation prompts
                    // (for all backends) can reference the serialized tool payload without updating UI state.
                    let toolMessage = ChatVM.Msg(
                        role: "tool",
                        text: toolJSON,
                        timestamp: Date()
                    )
                    continuationHistory.append(toolMessage)
                    // For MLX models, include the original question so they resume properly.
                    if self.loadedFormat == .mlx {
                        let question = history.last(where: { $0.role == "user" })?.text ?? ""
                        let nudgeText: String
                        if question.isEmpty {
                            nudgeText = "Respond to the user's original question using the tool results above. Continue where you left off and answer concisely."
                        } else {
                            nudgeText = "Respond to the original question: \(question) using the tool results above. Continue where you left off and answer concisely."
                        }
                        let nudge = ChatVM.Msg(
                            role: "user",
                            text: nudgeText,
                            timestamp: Date()
                        )
                        continuationHistory.append(nudge)
                    } else if self.loadedFormat == .slm {
                        // For Leap SLM, do not append a visible nudge to history.
                        // We'll send a hidden user message along with the tool results in the next turn.
                    }
                    
                    // We may need multiple short continuations if the SLM issues
                    // another tool call during the post-tool turn. Support a small
                    // loop to handle up to two additional tool calls.
                    var localHistory = continuationHistory
                    let (_, continuationStops, _) = self.buildPrompt(kind: self.currentKind, history: localHistory)

                    await MainActor.run {
                        if self.streamMsgs.indices.contains(outIdx) {
                            self.streamMsgs[outIdx].streaming = true
                        }
                    }

                    var remainingToolTurns = 2
                    var prefillRetryAttempts = 0
                    let maxPrefillRetries = 3
                    continuationLoop: while true {
                        var postToolPrompt: String = ""
                        var postToolInput: LLMInput? = nil
                        // A short guard to let the SLM fully quiesce after cancellation
                        // helps avoid transient Prefill aborted races in ExecuTorch backends.
                        if self.loadedFormat == .slm {
                            try? await Task.sleep(nanoseconds: 120_000_000) // ~120ms
                        }
                        // Ensure localHistory reflects latest streamed assistant text before rebuilding the prompt.
                        // Prefer the preserved pre-tool text when available so we avoid inline TOOL_RESULT markers
                        // that were injected into the UI transcript.
                        if localHistory.indices.contains(outIdx) {
                            let latestAssistantText: String
                            if let preserved = pendingAssistantText {
                                latestAssistantText = preserved
                            } else {
                                latestAssistantText = await MainActor.run {
                                    if self.streamMsgs.indices.contains(outIdx) {
                                        return self.streamMsgs[outIdx].text
                                    } else {
                                        return localHistory[outIdx].text
                                    }
                                }
                            }
                            localHistory[outIdx].text = latestAssistantText
                        }
                        // Build the prompt/messages for continuation
                        if self.loadedFormat == .slm {
                            let previousUser = history.last(where: { $0.role.lowercased() == "user" || $0.role == "🧑‍💻" })?.text ?? ""
                            let trimmedQuestion = previousUser.trimmingCharacters(in: .whitespacesAndNewlines)
                            let nudgeBody: String = {
                                if trimmedQuestion.isEmpty {
                                    return "With these search results, continue your earlier response. Do not call web search again unless explicitly requested."
                                }
                                return "With these results from search, respond to: \(trimmedQuestion). Do not call web search again; use the context you received."
                            }()
                            var slmHistory = localHistory
                            // Append a hidden user nudge so the prompt builder includes clear continuation guidance.
                            slmHistory.append(
                                ChatVM.Msg(
                                    role: "user",
                                    text: nudgeBody,
                                    timestamp: Date()
                                )
                            )
                            let toolPayload: String = (localHistory.last { $0.role == "tool" })?.text ?? toolJSON
                            postToolPrompt = nudgeBody
                            let toolMsg = ChatMessage(role: "tool", content: toolPayload)
                            let userMsg = ChatMessage(role: "user", content: nudgeBody)
                            postToolInput = LLMInput(.messages([toolMsg, userMsg]))
                        } else {
                            let (continuationPrompt, _, _) = self.buildPrompt(kind: self.currentKind, history: localHistory)
                            postToolPrompt = continuationPrompt
                            postToolInput = LLMInput.plain(postToolPrompt)
                        }

                        var continuation = ""
                        var nextToolJSON: String? = nil
                        let maxContTokens = Int(self.contextLimit * 0.4)
                        var contTokCount = 0
                        do {
                        // Stream continuation using the rebuilt prompt (SLM path reuses the ongoing Leap conversation).
                            guard let input = postToolInput else { break }
                            for try await t in try await client.textStream(from: input) {
                                if Task.isCancelled { break }
                                let trimmedT = t.trimmingCharacters(in: .whitespacesAndNewlines)

                                // Intercept additional tool calls emitted during continuation (SLM)
                                if trimmedT.hasPrefix("TOOL_CALL:") {
                                    if let (handled, trailing) = await interceptToolCallIfPresent(trimmedT, messageIndex: outIdx, chatVM: self) {
                                        await MainActor.run {
                                            if self.streamMsgs.indices.contains(outIdx) {
                                                self.streamMsgs[outIdx].usedWebSearch = true
                                            }
                                        }
                                        let json = handled.replacingOccurrences(of: "TOOL_RESULT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                                        nextToolJSON = json
                                        // Remember assistant text prior to this additional tool call
                                        pendingAssistantText = continuation
                                        // Append inline marker to transcript for continuity
                                        let inlineTokens = handled + "\n"
                                        let appendChunk = nonOverlappingDelta(newChunk: inlineTokens, existing: continuation)
                                        continuation += appendChunk
                                        await MainActor.run {
                                            if self.streamMsgs.indices.contains(outIdx) {
                                                self.streamMsgs[outIdx].text.append(contentsOf: appendChunk)
                                            }
                                        }
                                        if let trailing, !trailing.isEmpty {
                                            continuation += trailing
                                            await MainActor.run {
                                                if self.streamMsgs.indices.contains(outIdx) {
                                                    self.streamMsgs[outIdx].text.append(contentsOf: trailing)
                                                }
                                            }
                                        }
                                        // Stop the current continuation stream before starting the next tool turn
                                        client.cancelActive()
                                        break
                                    }
                                }
                                if trimmedT.hasPrefix("TOOL_RESULT:") {
                                    let json = trimmedT.replacingOccurrences(of: "TOOL_RESULT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    pendingAssistantText = continuation
                                    nextToolJSON = json
                                    // Also surface the token inline for UI continuity
                                    let appendChunk = nonOverlappingDelta(newChunk: t + "\n", existing: continuation)
                                    continuation += appendChunk
                                    await MainActor.run {
                                        if self.streamMsgs.indices.contains(outIdx) {
                                            self.streamMsgs[outIdx].text.append(contentsOf: appendChunk)
                                        }
                                    }
                                    // Stop the current continuation stream before starting the next tool turn
                                    client.cancelActive()
                                    break
                                }

                                let appendChunk = nonOverlappingDelta(newChunk: t, existing: continuation)
                                continuation += appendChunk
                                contTokCount += 1

                                await MainActor.run {
                                    if self.streamMsgs.indices.contains(outIdx) {
                                        self.streamMsgs[outIdx].text.append(contentsOf: appendChunk)
                                    }
                                }
                                let fullText: String = await MainActor.run {
                                    if self.streamMsgs.indices.contains(outIdx) {
                                        return self.streamMsgs[outIdx].text
                                    } else { return continuation }
                                }
                                await self.handleRollingThoughts(raw: fullText, messageIndex: outIdx)

                                if let sfx = continuationStops.first(where: { continuation.hasSuffix($0) }) {
                                    let lastOpen = fullText.range(of: "<think>", options: .backwards)
                                    let lastClose = fullText.range(of: "</think>", options: .backwards)
                                    let insideThink = {
                                        if let o = lastOpen {
                                            if let c = lastClose { return o.lowerBound > c.lowerBound }
                                            return true
                                        }
                                        return false
                                    }()
                                    if !insideThink {
                                        continuation = String(continuation.dropLast(sfx.count))
                                        break
                                    }
                                }
                                if contTokCount >= maxContTokens { break }
                            }
                        } catch {
                            // Adaptive exponential backoff for transient SLM prefill races
                            let lower = error.localizedDescription.lowercased()
                            if self.loadedFormat == .slm && (lower.contains("prefill aborted") || lower.contains("interrupted")) {
                                if prefillRetryAttempts < maxPrefillRetries {
                                    let attempt = prefillRetryAttempts
                                    prefillRetryAttempts += 1
                                    // 250ms, 500ms, 1000ms
                                    let backoff = UInt64(250_000_000 * Int(pow(2.0, Double(attempt))))
                                    await logger.log("[ChatVM] Prefill aborted. Retrying in \(backoff / 1_000_000)ms (attempt \(attempt + 1)/\(maxPrefillRetries)).")
                                    try? await Task.sleep(nanoseconds: backoff)
                                    continue continuationLoop
                                } else {
                                    await logger.log("[ChatVM] Prefill aborted after \(maxPrefillRetries) retries. Failing.")
                                }
                            }
                            await MainActor.run {
                                if self.streamMsgs.indices.contains(outIdx) {
                                    self.streamMsgs[outIdx].text.append("\n⚠️ " + error.localizedDescription)
                                }
                            }
                        }

                        // If the continuation produced no tokens and no error, it's often the same
                        // transient prefill race. Retry a few times with backoff for SLM models.
                        if self.loadedFormat == .slm && continuation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && nextToolJSON == nil {
                            if prefillRetryAttempts < maxPrefillRetries {
                                let attempt = prefillRetryAttempts
                                prefillRetryAttempts += 1
                                let backoff = UInt64(150_000_000 * Int(pow(2.0, Double(attempt)))) // 150ms, 300ms, 600ms
                                await logger.log("[ChatVM] Empty continuation. Retrying in \(backoff / 1_000_000)ms (attempt \(attempt + 1)/\(maxPrefillRetries)).")
                                try? await Task.sleep(nanoseconds: backoff)
                                continue continuationLoop
                            }
                        }

                        // If another tool was requested, inject it and loop again
                        if let json = nextToolJSON, remainingToolTurns > 0 {
                            remainingToolTurns -= 1
                            let toolMsg = ChatVM.Msg(role: "tool", text: json, timestamp: Date())
                            localHistory.append(toolMsg)
                            // For MLX we may extend localHistory with a hidden nudge; for SLM, we only
                            // construct hidden messages on the next loop iteration and do not reflect in UI.
                            if self.loadedFormat == .mlx {
                                let previousUser = history.last(where: { $0.role.lowercased() == "user" || $0.role == "🧑‍💻" })?.text ?? ""
                                let results = json
                                let nudge = ChatVM.Msg(
                                    role: "user",
                                    text: "Continue your response using the latest tool results.\n\nQuestion: \(previousUser)\n\nResults:\n\(results)",
                                    timestamp: Date()
                                )
                                localHistory.append(nudge)
                            }
                            continue continuationLoop
                        }
                        break
                    }

                    await MainActor.run {
                        if self.streamMsgs.indices.contains(outIdx) {
                            self.streamMsgs[outIdx].streaming = false
                        }
                    }
                    await MainActor.run { self.currentContinuationTask = nil }
                }
            }
        }
        // Do not immediately clear the banner here; allow the delayed clear above
        currentInjectedTokenOverhead = 0
        pendingImageURLs.removeAll()
    }

    // maybeAutoTitle removed in favor of using the first user query as title

    private func parse(_ text: String, toolCalls: [ToolCall]? = nil) -> [Piece] {
        // First parse code blocks
        let codeBlocks = Self.parseCodeBlocks(text)
        
        // Then parse think tags within each text piece
        var finalPieces: [Piece] = []
        var toolCallIndex = 0 // Track which tool call we're currently processing
        
        for piece in codeBlocks {
            switch piece {
            case .code(let code, let lang):
                // Detect tool-call JSON/XML inside fenced code blocks and surface a tool placeholder instead
                var insertedToolFromCodeBlock = false
                let codeSub = code[...]
                var tmp = codeSub
                // 1) XML-style <tool_call> blocks inside code fences
                while let callTag = tmp.range(of: "<tool_call>") {
                    tmp = tmp[callTag.upperBound...]
                    if let end = tmp.range(of: "</tool_call>") {
                        tmp = tmp[end.upperBound...]
                    } else {
                        tmp = tmp[tmp.endIndex...]
                    }
                    finalPieces.append(.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 { toolCallIndex += 1 }
                    insertedToolFromCodeBlock = true
                }
                // 2) TOOL_CALL:/TOOL_RESULT markers inside code fences
                tmp = codeSub
                while let callRange = tmp.range(of: "TOOL_CALL:") {
                    tmp = tmp[callRange.upperBound...]
                    finalPieces.append(.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 { toolCallIndex += 1 }
                    insertedToolFromCodeBlock = true
                }
                // 3) Bare JSON tool-call object inside code fences
                tmp = codeSub
                var searchStart = tmp.startIndex
                scanJSONInCode: while let braceStart = tmp[searchStart...].firstIndex(of: "{") {
                    if let braceEnd = findMatchingBrace(in: tmp, startingFrom: braceStart) {
                        let candidate = tmp[braceStart...braceEnd]
                        if (candidate.contains("\"tool_name\"") || candidate.contains("\"name\"") || candidate.contains("\"tool\"")) &&
                           (candidate.contains("\"arguments\"") || candidate.contains("\"args\"")) {
                            finalPieces.append(.tool(toolCallIndex))
                            if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 { toolCallIndex += 1 }
                            insertedToolFromCodeBlock = true
                            // Continue after this JSON object in case of multiple
                            searchStart = tmp.index(after: braceEnd)
                            continue scanJSONInCode
                        }
                        searchStart = tmp.index(after: braceEnd)
                        continue scanJSONInCode
                    } else {
                        break scanJSONInCode
                    }
                }
                if !insertedToolFromCodeBlock {
                    finalPieces.append(.code(code, language: lang))
                }
            case .text(let t):
                // Parse think tags in text
                var rest = t[...]
                // Detect inline tool call start(s) and replace with tool box, preserving following text
                while let callTag = rest.range(of: "<tool_call>") {
                    if callTag.lowerBound > rest.startIndex {
                        finalPieces.append(.text(String(rest[..<callTag.lowerBound])))
                    }
                    // Skip over the tool call JSON content
                    rest = rest[callTag.upperBound...]
                    if let end = rest.range(of: "</tool_call>") {
                        rest = rest[end.upperBound...]
                    } else {
                        // If no explicit closing tag, drop everything after marker
                        rest = rest[rest.endIndex...]
                    }
                    // Use the current tool call index and increment for next one
                    finalPieces.append(.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                        toolCallIndex += 1
                    }
                }
                // Detect TOOL_CALL: inline markers repeatedly and hide JSON until the next tool response marker if present
                while let callRange = rest.range(of: "TOOL_CALL:") {
                    if callRange.lowerBound > rest.startIndex {
                        finalPieces.append(.text(String(rest[..<callRange.lowerBound])))
                    }
                    var after = rest[callRange.upperBound...]
                    if let nextResp = (after.range(of: "<tool_response>") ?? after.range(of: "TOOL_RESULT:")) {
                        rest = after[nextResp.lowerBound...]
                    } else if let nl = after.firstIndex(of: "\n") {
                        rest = after[nl...]
                    } else {
                        rest = rest[rest.endIndex...]
                    }
                    // Use the current tool call index and increment for next one
                    finalPieces.append(.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                        toolCallIndex += 1
                    }
                }
                // Detect inline tool result JSON markers repeatedly and render tool box instead of raw JSON
                while let toolRange = rest.range(of: "<tool_response>") ?? rest.range(of: "TOOL_RESULT:") {
                    // Emit text before the tool block
                    if toolRange.lowerBound > rest.startIndex {
                        finalPieces.append(.text(String(rest[..<toolRange.lowerBound])))
                    }
                    // Determine which marker we matched and skip over its content while
                    // preserving any trailing text after the tool result JSON.
                    if rest[toolRange].hasPrefix("<tool_response>") {
                        rest = rest[toolRange.upperBound...]
                        if let end = rest.range(of: "</tool_response>") {
                            rest = rest[end.upperBound...]
                        } else {
                            // If no explicit closing tag, drop everything after marker
                            rest = rest[rest.endIndex...]
                        }
                    } else {
                        // Skip TOOL_RESULT JSON payloads. These can be objects or arrays.
                        rest = rest[toolRange.upperBound...]
                        // Advance past any whitespace
                        var idx = rest.startIndex
                        while idx < rest.endIndex && rest[idx].isWhitespace { idx = rest.index(after: idx) }
                        if idx < rest.endIndex {
                            if rest[idx] == "[" {
                                if let close = findMatchingBracket(in: rest, startingFrom: idx) {
                                    rest = rest[rest.index(after: close)...]
                                } else {
                                    // Incomplete array JSON; drop remainder until more tokens arrive
                                    rest = rest[rest.endIndex...]
                                }
                            } else if rest[idx] == "{" {
                                if let close = findMatchingBrace(in: rest, startingFrom: idx) {
                                    rest = rest[rest.index(after: close)...]
                                } else {
                                    // Incomplete object JSON; drop remainder until more tokens arrive
                                    rest = rest[rest.endIndex...]
                                }
                            } else {
                                // Unknown payload; be conservative and drop remainder
                                rest = rest[rest.endIndex...]
                            }
                        } else {
                            rest = rest[rest.endIndex...]
                        }
                    }
                    // Tool response doesn't increment the index since it's for the same tool call
                    finalPieces.append(.tool(toolCallIndex))
                }
                // Parse all think blocks that remain
                while let s = rest.range(of: "<think>") {
                    if s.lowerBound > rest.startIndex {
                        finalPieces.append(.text(String(rest[..<s.lowerBound])))
                    }
                    rest = rest[s.upperBound...]
                    if let e = rest.range(of: "</think>") {
                        finalPieces.append(.think(String(rest[..<e.lowerBound]), done: true))
                        rest = rest[e.upperBound...]
                    } else {
                        finalPieces.append(.think(String(rest), done: false))
                        rest = rest[rest.endIndex...]
                    }
                }
                if !rest.isEmpty { finalPieces.append(.text(String(rest))) }
            case .think:
                // This shouldn't happen from parseCodeBlocks
                break
            case .tool(_):
                // Tool blocks are handled at render time; ignore here
                break
            }
        }
        
        return finalPieces
    }

    // Helper to find matching closing brace for a JSON object within a substring,
    // honoring string literals and escape sequences.
    private func findMatchingBrace(in text: Substring, startingFrom startIndex: Substring.Index) -> Substring.Index? {
        guard text[startIndex] == "{" else { return nil }
        var braceCount = 0
        var inString = false
        var escapeNext = false
        var idx = startIndex
        while idx < text.endIndex {
            let char = text[idx]
            if escapeNext {
                escapeNext = false
                idx = text.index(after: idx)
                continue
            }
            if char == "\\" && inString {
                escapeNext = true
                idx = text.index(after: idx)
                continue
            }
            if char == "\"" {
                inString.toggle()
                idx = text.index(after: idx)
                continue
            }
            if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        return idx
                    }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    // Helper to find matching closing bracket for a JSON array, honoring strings and escapes
    private func findMatchingBracket(in text: Substring, startingFrom startIndex: Substring.Index) -> Substring.Index? {
        guard text[startIndex] == "[" else { return nil }
        var depth = 0
        var inString = false
        var escapeNext = false
        var idx = startIndex
        while idx < text.endIndex {
            let char = text[idx]
            if escapeNext {
                escapeNext = false
                idx = text.index(after: idx)
                continue
            }
            if char == "\\" && inString {
                escapeNext = true
                idx = text.index(after: idx)
                continue
            }
            if char == "\"" { inString.toggle() }
            if !inString {
                if char == "[" { depth += 1 }
                else if char == "]" {
                    depth -= 1
                    if depth == 0 { return idx }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    

    // Inserts retrieval context inside the current template's user section so BOS/control tokens remain valid.
    // If the template isn't recognized, it falls back to prefixing a "Context:" block.
    private func injectContextIntoPrompt(original: String, context: String, kind: ModelKind) -> String {
        let note = """
        Use the following information to answer the question. Cite sources using bracketed numbers like [1], [2], etc.
        """
        let block = note + context + "\n\n"
        let s = original
        switch templateKind() ?? kind {
        case .llama3:
            // <|start_header_id|>user<|end_header_id|> ... <|eot_id|>
            let userOpen = "<|start_header_id|>user<|end_header_id|>\n"
            let eot = "<|eot_id|>"
            if let openRange = s.range(of: userOpen) {
                if let closeRange = s.range(of: eot, range: openRange.upperBound..<s.endIndex) {
                    var out = s
                    out.insert(contentsOf: block, at: closeRange.lowerBound)
                    return out
                }
            }
        case .gemma, .qwen, .smol, .lfm:
            // <|im_start|>user\n ... <|im_end|>
            let userOpen = "<|im_start|>user\n"
            let userClose = "<|im_end|>"
            if let openRange = s.range(of: userOpen) {
                if let closeRange = s.range(of: userClose, range: openRange.upperBound..<s.endIndex) {
                    var out = s
                    out.insert(contentsOf: block, at: closeRange.lowerBound)
                    return out
                }
            }
        case .mistral:
            // [INST] ... [/INST]
            let open = "[INST]"
            let close = "[/INST]"
            if let openRange = s.range(of: open) {
                if let closeRange = s.range(of: close, range: openRange.upperBound..<s.endIndex) {
                    var out = s
                    out.insert(contentsOf: "\n" + block, at: closeRange.lowerBound)
                    return out
                }
            }
        case .phi:
            // <|user|> ... <|assistant|>
            let uOpen = "<|user|>"
            let aOpen = "<|assistant|>"
            if let openRange = s.range(of: uOpen) {
                if let closeRange = s.range(of: aOpen, range: openRange.upperBound..<s.endIndex) {
                    var out = s
                    out.insert(contentsOf: "\n" + block, at: closeRange.lowerBound)
                    return out
                }
            }
        default:
            break
        }
        return block + s
    }
}

// Utility helpers used by `ChatVM`.
private extension ChatVM {
    // Inserts image placeholder tokens into the current template's latest user section so BOS/control tokens remain valid.
    // If the template isn't recognized, it falls back to prefixing simple placeholders at the beginning.
    private func injectImagesIntoPrompt(original: String, imageCount: Int, kind: ModelKind) -> String {
        guard imageCount > 0 else { return original }
        let s = original
        let tmpl = templateKind() ?? kind
        func placeholders(chatml: Bool) -> String {
            let token = chatml ? "<|image|>\n" : "<image>\n"
            return String(repeating: token, count: max(1, imageCount))
        }
        switch tmpl {
        case .llama3:
            // <|start_header_id|>user<|end_header_id|> ... <|eot_id|>
            let userOpen = "<|start_header_id|>user<|end_header_id|>\n"
            let eot = "<|eot_id|>"
            if let open = s.range(of: userOpen), let close = s.range(of: eot, range: open.upperBound..<s.endIndex) {
                var out = s
                out.insert(contentsOf: placeholders(chatml: false), at: close.lowerBound)
                return out
            }
        case .gemma, .qwen, .smol, .lfm:
            // ChatML-style or Gemma turn: <|im_start|>user\n ... <|im_end|>
            let userOpen = "<|im_start|>user\n"
            let userClose = "<|im_end|>"
            if let open = s.range(of: userOpen, options: .backwards), let close = s.range(of: userClose, range: open.upperBound..<s.endIndex) {
                var out = s
                out.insert(contentsOf: placeholders(chatml: true), at: close.lowerBound)
                return out
            }
            // Gemma-turn variant: <start_of_turn>user\n ... <end_of_turn>
            let gOpen = "<start_of_turn>user\n"
            let gClose = "<end_of_turn>"
            if let open = s.range(of: gOpen, options: .backwards), let close = s.range(of: gClose, range: open.upperBound..<s.endIndex) {
                var out = s
                out.insert(contentsOf: placeholders(chatml: false), at: close.lowerBound)
                return out
            }
        case .mistral:
            // [INST] ... [/INST]
            let openTag = "[INST]"
            let closeTag = "[/INST]"
            if let open = s.range(of: openTag, options: .backwards), let close = s.range(of: closeTag, range: open.upperBound..<s.endIndex) {
                var out = s
                out.insert(contentsOf: "\n" + placeholders(chatml: false), at: close.lowerBound)
                return out
            }
        case .phi:
            // <|user|> ... <|assistant|>
            let uOpen = "<|user|>"
            let aOpen = "<|assistant|>"
            if let open = s.range(of: uOpen, options: .backwards), let close = s.range(of: aOpen, range: open.upperBound..<s.endIndex) {
                var out = s
                out.insert(contentsOf: "\n" + placeholders(chatml: false), at: close.lowerBound)
                return out
            }
        default:
            break
        }
        // Fallback: prefix placeholders
        return placeholders(chatml: false) + s
    }
    static func metalQuant(from url: URL) -> String? {
        let name = url.lastPathComponent
        if let r = name.range(of: #"q[0-9][A-Za-z0-9_]*"#, options: .regularExpression) {
            return String(name[r])
        }
        return nil
    }
    func templateKind() -> ModelKind? {
        guard let t = promptTemplate?.lowercased() else { return nil }
        if t.contains("<|begin_of_text|>") { return .llama3 }
        if t.contains("[inst]") { return .mistral }
        if t.contains("<|startoftext|>") { return .lfm }
        if t.contains("<|im_start|>") {
            if currentKind == .gemma { return .gemma }
            if currentKind == .lfm { return .lfm }
            // Smol and Qwen both serialize with ChatML tokens by default
            if currentKind == .smol { return .smol }
            if currentKind == .internlm { return .internlm }
            if currentKind == .yi { return .yi }
            return .qwen
        }
        // DeepSeek may use distinct BOS and role tags; detect via placeholders if present
        if (t.contains("<|user|>") && t.contains("<|assistant|>")) ||
           (t.contains("<｜user｜>") && t.contains("<｜assistant｜>")) ||
            t.contains("<｜begin▁of▁sentence｜>") {
            return .deepseek
        }
        if t.contains("<|system|>") { return .phi }
        return nil
    }

    /// Builds a prompt for the underlying model from a message history.
    /// Example: Gemma single turn history `["Hi"]` → prompt ends with
    /// "<|im_start|>assistant\n" and user sees no control tokens.
    func buildPrompt(kind: ModelKind, history: [ChatVM.Msg]) -> (String, [String], Int) {
        // Use the unified formatter to prepare messages vs plain prompt
        let cfMessages: [ChatFormatter.Message] = history.map { m in
            let roleLower = m.role.lowercased()
            let normalizedRole: String
            if roleLower == "🧑‍💻".lowercased() { normalizedRole = "user" }
            else if roleLower == "🤖".lowercased() { normalizedRole = "assistant" }
            else { normalizedRole = roleLower }
            return ChatFormatter.Message(role: normalizedRole, content: m.text)
        }
        let rendered = prepareForGeneration(messages: history, system: systemPromptText)
        switch rendered {
        case .messages(let arr):
            // Convert back to ChatVM.Msg for our renderer
            let msgs: [ChatVM.Msg] = arr.map { ChatVM.Msg(role: $0.role, text: $0.content) }
            return PromptBuilder.build(template: promptTemplate, family: kind, messages: msgs)
        case .plain(let s):
            // Let caller pick default stops; provide generous token budget
            return (s, [], 8192)
        }
    }

    /// New unified chat preparation that returns either a messages array (for chat-aware backends)
    /// or a single plain prompt string for completion-style backends.
    func prepareForGeneration(messages: [ChatVM.Msg], system: String) -> ChatFormatter.RenderedPrompt {
        let modelId: String = loadedURL?.lastPathComponent ?? "unknown"
        var cf = ChatFormatter.shared
        let family = currentKind

        // Convert to ChatFormatter.Message list (preserve order and roles)
        let msgs: [ChatFormatter.Message] = messages.map { m in
            ChatFormatter.Message(role: m.role.lowercased() == "🧑‍💻".lowercased() ? "user" : (m.role.lowercased() == "🤖".lowercased() ? "assistant" : m.role.lowercased()), content: m.text)
        }

        let rendered = cf.prepareForGeneration(
            modelId: modelId,
            template: promptTemplate,
            family: family,
            messages: msgs,
            system: system
        )

        // Runtime validation: ensure system content appears before first user span
        func validate(_ prompt: String, sys: String) -> Bool {
            let s = sys.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return true }
            let lower = prompt.lowercased()
            let sysIdx = lower.range(of: s.lowercased())?.lowerBound
            let userIdx = lower.range(of: "user:")?.lowerBound
            if let sysIdx, let userIdx { return sysIdx < userIdx }
            return sysIdx != nil
        }

        switch rendered {
        case .messages(let arr):
            // Cheap join to validate order without changing the authoritative structure
            let flat = arr.map { "\($0.role.capitalized): \($0.content)" }.joined(separator: "\n")
            if !validate(flat, sys: system) {
                Task { await logger.log("[Warn][Prompt] System text missing after render; model=\(modelId) hash=\(system.hashValue)") }
                // Conservative fallback: re-render via inline-first-user path
                var cf2 = ChatFormatter.shared
                let re = cf2.prepareForGeneration(
                    modelId: modelId,
                    template: promptTemplate,
                    family: family,
                    messages: arr.map { ChatFormatter.Message(role: $0.role, content: $0.content) },
                    system: system,
                    forceInlineWhenTemplatePresent: true
                )
                return re
            }
            return .messages(arr)
        case .plain(let s):
            if !validate(s, sys: system) {
                Task { await logger.log("[Warn][Prompt] System text missing in plain render; model=\(modelId) hash=\(system.hashValue)") }
                // For plain, prepend explicitly
                let fixed = "System: " + system + "\n\n" + s
                return .plain(fixed)
            }
            return .plain(s)
        }
    }

    /// Removes any model specific control tokens from the raw output.
    func cleanOutput(_ raw: String, kind: ModelKind) -> String {
        var t = raw
        let tmplKind = templateKind() ?? kind
        switch tmplKind {
        case .gemma, .qwen, .smol, .lfm:
            if tmplKind == .gemma && gemmaAutoTemplated {
                t = t.replacingOccurrences(of: "<start_of_turn>model", with: "")
                t = t.replacingOccurrences(of: "<start_of_turn>user", with: "")
                t = t.replacingOccurrences(of: "<start_of_turn>system", with: "")
                t = t.replacingOccurrences(of: "<end_of_turn>", with: "")
                t = t.replacingOccurrences(of: "<bos>", with: "")
                t = t.replacingOccurrences(of: "<eos>", with: "")
            } else {
                t = t.replacingOccurrences(of: "<|im_start|>assistant", with: "")
                t = t.replacingOccurrences(of: "<|im_start|>user", with: "")
                t = t.replacingOccurrences(of: "<|im_end|>", with: "")
                t = t.replacingOccurrences(of: "<\\|im_.*?\\|>\n?", with: "", options: .regularExpression)
            }
        case .internlm:
            // ChatML-like tokens
            t = t.replacingOccurrences(of: "<|im_start|>assistant", with: "")
            t = t.replacingOccurrences(of: "<|im_start|>user", with: "")
            t = t.replacingOccurrences(of: "<|im_start|>system", with: "")
            t = t.replacingOccurrences(of: "<|im_end|>", with: "")
        case .yi:
            t = t.replacingOccurrences(of: "<|startoftext|>", with: "")
            t = t.replacingOccurrences(of: "<|im_start|>assistant", with: "")
            t = t.replacingOccurrences(of: "<|im_start|>user", with: "")
            t = t.replacingOccurrences(of: "<|im_end|>", with: "")
        case .deepseek:
            // Remove DeepSeek control tokens (canonical fullwidth; also strip legacy/ascii variants)
            t = t.replacingOccurrences(of: "<｜begin▁of▁sentence｜>", with: "")
            t = t.replacingOccurrences(of: "<｜User｜>", with: "")
            t = t.replacingOccurrences(of: "<｜Assistant｜>", with: "")
            // Legacy/weird variants (left in for robustness)
            t = t.replacingOccurrences(of: "<攼 begin▁of▁sentence放>", with: "")
            t = t.replacingOccurrences(of: "<|User|>", with: "")
            t = t.replacingOccurrences(of: "<|Assistant|>", with: "")
        case .llama3:
            t = t.replacingOccurrences(of: "<|begin_of_text|>", with: "")
            t = t.replacingOccurrences(of: "<|start_header_id|>", with: "")
            t = t.replacingOccurrences(of: "<|end_header_id|>", with: "")
            t = t.replacingOccurrences(of: "<|eot_id|>", with: "")
            t = t.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
        case .mistral:
            t = t.replacingOccurrences(of: "<s>", with: "")
            t = t.replacingOccurrences(of: "</s>", with: "")
            t = t.replacingOccurrences(of: "[INST]", with: "")
            t = t.replacingOccurrences(of: "[/INST]", with: "")
        case .phi:
            t = t.replacingOccurrences(of: "<|system|>", with: "")
            t = t.replacingOccurrences(of: "<|user|>", with: "")
            t = t.replacingOccurrences(of: "<|assistant|>", with: "")
            t = t.replacingOccurrences(of: "<|end|>", with: "")
        default:
            t = t.replacingOccurrences(of: "System:", with: "")
            t = t.replacingOccurrences(of: "User:", with: "")
            if t.hasPrefix("Assistant:") {
                t = String(t.dropFirst("Assistant:".count))
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits text into `.text` and `.code` pieces based on fenced triple backticks.
    /// Recognizes optional language hints immediately following the opening ```.
    static func parseCodeBlocks(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        var currentText = ""
        let lines = text.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                if !currentText.isEmpty {
                    pieces.append(.text(currentText.trimmingCharacters(in: .newlines)))
                    currentText = ""
                }

                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1

                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }

                if !codeLines.isEmpty {
                    let code = codeLines.joined(separator: "\n")
                    pieces.append(.code(code, language: lang.isEmpty ? nil : lang))
                }
            } else {
                currentText += (currentText.isEmpty ? "" : "\n") + line
            }
            i += 1
        }

        if !currentText.isEmpty {
            pieces.append(.text(currentText.trimmingCharacters(in: .newlines)))
        }

        return pieces
    }

    // Heuristic for GGUF VLMs when Hub metadata is unavailable (offline or missing tags)
    internal static nonisolated func guessLlamaVisionModel(from url: URL) -> Bool {
        // Prefer a definitive architectural check for a multimodal projector
        return GGUFMetadata.hasMultimodalProjector(at: url)
    }

    @MainActor
    func savePendingImage(_ image: UIImage) async {
        // Persist to temporary directory so we can pass file paths into model clients
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("noema_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = image.jpegData(compressionQuality: 0.9) {
            let url = dir.appendingPathComponent(UUID().uuidString + ".jpg")
            try? data.write(to: url)
            pendingImageURLs.append(url)
        }
    }

    @MainActor
    func removePendingImage(at index: Int) {
        guard pendingImageURLs.indices.contains(index) else { return }
        let url = pendingImageURLs.remove(at: index)
        try? FileManager.default.removeItem(at: url)
    }
    
    /// Handle rolling thoughts for <think> tags during streaming
    private func handleRollingThoughts(raw: String, messageIndex: Int) async {
        // Parse think blocks from the raw text
        let thinkBlocks = parseThinkBlocks(from: raw)
        
        await MainActor.run {
            // Update or create rolling thought view models for each think block
            for (index, thinkBlock) in thinkBlocks.enumerated() {
                // Use message UUID for stable keys so view can find the matching view model
                guard messageIndex >= 0 && messageIndex < streamMsgs.count else { continue }
                let msgId = streamMsgs[messageIndex].id.uuidString
                let thinkKey = "message-\(msgId)-think-\(index)"

                // Skip empty think blocks
                guard !thinkBlock.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                
                if let existingViewModel = rollingThoughtViewModels[thinkKey] {
                    // Check if we need to update the content
                    if existingViewModel.fullText != thinkBlock.content {
                        // Create a stream for only the new content
                        let newContent = String(thinkBlock.content.dropFirst(existingViewModel.fullText.count))
                        if !newContent.isEmpty {
                            let tokens = AsyncStream<String> { continuation in
                                Task {
                                    // Stream only the new content with slight delay for visual effect
                                    // Yield in larger chunks to reduce flicker and avoid altering visual layout
                                    let chunkSize = 16
                                    var buffer = ""
                                    buffer.reserveCapacity(chunkSize)
                                    for ch in newContent {
                                        buffer.append(ch)
                                        if buffer.count >= chunkSize {
                                            continuation.yield(buffer)
                                            buffer.removeAll(keepingCapacity: true)
                                        }
                                    }
                                    if !buffer.isEmpty { continuation.yield(buffer) }
                                    continuation.finish()
                                }
                            }
                            let tokenStream = ChatTokenStream(tokens: tokens)
                            existingViewModel.append(with: tokenStream)
                        }
                    }
                    
                    // Only mark complete when the final </think> has arrived.
                    // If the token stream is still appending, defer completion until it ends.
                    // Call finish() even when expanded so the logical completion flag is set;
                    // finish() preserves expanded UI but marks the box as complete.
                    if thinkBlock.isComplete && existingViewModel.phase != .complete {
                        if existingViewModel.fullText == thinkBlock.content {
                            existingViewModel.finish()
                            // Persist state promptly so boxes survive app/model transitions
                            let storageKey = "RollingThought." + thinkKey
                            existingViewModel.saveState(forKey: storageKey)
                        } else {
                            existingViewModel.deferCompletionUntilStreamEnds()
                        }
                    }
                } else {
                    // Create new rolling thought view model and start streaming
                    let viewModel = RollingThoughtViewModel()
                    
                    // Create token stream from the think block content
                    let tokens = AsyncStream<String> { continuation in
                        Task {
                            // Stream content in moderate chunks to avoid jitter while preserving order
                            let text = thinkBlock.content
                            let chunkSize = 32
                            var idx = text.startIndex
                            while idx < text.endIndex {
                                let next = text.index(idx, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
                                let slice = String(text[idx..<next])
                                continuation.yield(slice)
                                idx = next
                            }
                            continuation.finish()
                        }
                    }
                    
                    let tokenStream = ChatTokenStream(tokens: tokens)
                    viewModel.start(with: tokenStream)
                    // If we already saw the closing tag, ensure the box completes once the current
                    // character stream finishes, even if the model stops emitting more tokens.
                    if thinkBlock.isComplete {
                        viewModel.deferCompletionUntilStreamEnds()
                    }
                    
                    rollingThoughtViewModels[thinkKey] = viewModel
                }
            }
        }
    }
    
    /// Parse think blocks from raw text
    private func parseThinkBlocks(from text: String) -> [(content: String, isComplete: Bool)] {
        var blocks: [(String, Bool)] = []
        var rest = text[...]
        
        while let start = rest.range(of: "<think>") {
            rest = rest[start.upperBound...]
            if let end = rest.range(of: "</think>") {
                let content = String(rest[..<end.lowerBound])
                // Strip any nested or stray think tags inside the content to avoid leaking markers
                let sanitized = content.replacingOccurrences(of: "<think>", with: "").replacingOccurrences(of: "</think>", with: "")
                blocks.append((sanitized, true))
                rest = rest[end.upperBound...]
            } else {
                let content = String(rest)
                let sanitized = content.replacingOccurrences(of: "<think>", with: "").replacingOccurrences(of: "</think>", with: "")
                blocks.append((sanitized, false))
                break
            }
        }
        
        return blocks
    }
    
    /// Recreate rolling thought view models for existing messages
    private func recreateRollingThoughtViewModels() {
        // Build allowed keys for current session and content map
        var allowedKeys: Set<String> = []
        var keyToContent: [String: (content: String, isComplete: Bool)] = [:]
        for msg in msgs {
            guard msg.role == "🤖" || msg.role.lowercased() == "assistant" else { continue }
            let blocks = parseThinkBlocks(from: msg.text)
            for (idx, block) in blocks.enumerated() {
                let content = block.content
                let isComplete = block.isComplete
                guard !content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else { continue }
                let key = "message-\(msg.id.uuidString)-think-\(idx)"
                allowedKeys.insert(key)
                keyToContent[key] = (content, isComplete)
            }
        }

        // Remove stale keys that do not belong to the active session anymore
        for key in rollingThoughtViewModels.keys where !allowedKeys.contains(key) {
            rollingThoughtViewModels[key]?.cancel()
            rollingThoughtViewModels.removeValue(forKey: key)
        }

        // Create missing view models for newly detected think blocks; preserve existing ones
        for key in allowedKeys where rollingThoughtViewModels[key] == nil {
            let vm = RollingThoughtViewModel()
            if let tuple = keyToContent[key] {
                vm.fullText = tuple.content
                vm.updateRollingLines()
                vm.phase = tuple.isComplete ? .complete : .expanded
            }
            rollingThoughtViewModels[key] = vm
        }
    }
}

// MARK: –– Floating menu -----------------------------------------------------

// URLSession downloadWithProgress moved to URLSession+DownloadWithProgress.swift

}
