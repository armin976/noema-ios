// Noema.swift
// Requires Swift Concurrency (iOS 17+).

import SwiftUI
import Foundation
import RelayKit
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif
@_exported import Foundation

// Import RollingThought functionality through NoemaPackages
import NoemaPackages

// Removed LocalLLMClient MLX path in favor of mlx-swift/mlx-swift-examples integration
// Using our own llama.cpp implementation instead of LocalLLMClientLlama
#if canImport(LeapSDK)
import LeapSDK
#endif
#if canImport(MLX)
import MLX
#endif

#if canImport(UIKit)
private extension UIImage {
    func resizedDown(to targetSize: CGSize) -> UIImage? {
        let maxW = max(1, Int(targetSize.width))
        let maxH = max(1, Int(targetSize.height))
        // If already smaller than target, skip expensive work
        if size.width <= CGFloat(maxW) && size.height <= CGFloat(maxH) { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: maxW, height: maxH), format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(x: 0, y: 0, width: CGFloat(maxW), height: CGFloat(maxH)))
        }
    }
}
#endif

private func currentDeviceWidth() -> CGFloat {
#if os(visionOS)
    return 1024
#elseif canImport(UIKit)
    return UIScreen.main.bounds.width
#elseif canImport(AppKit)
    return NSScreen.main?.frame.width ?? 1024
#else
    return 1024
#endif
}

@MainActor
private func performMediumImpact() {
#if os(iOS)
    Haptics.impact(.medium)
#endif
}

#if os(macOS)
private final class MacNonDraggableView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct MacWindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> MacNonDraggableView {
        MacNonDraggableView(frame: .zero)
    }

    func updateNSView(_ nsView: MacNonDraggableView, context: Context) {}
}
#endif

extension View {
    @ViewBuilder
    func macWindowDragDisabled() -> some View {
#if os(macOS)
        self.background(MacWindowDragBlocker().allowsHitTesting(false))
#else
        self
#endif
    }
}

// ---------------------------------------------------------------------------
// Temporary stubs for new SwiftUI modifiers used by iOS 26. These are no‑ops
// here so the project can compile on older toolchains.

enum TabBarMinimizeBehavior { case none, onScrollDown }
extension View {
    func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View { self }
    func tabViewBottomAccessory(alignment: Alignment = .center, @ViewBuilder content: () -> some View) -> some View { self }
}

enum ModelKind { case gemma, llama3, qwen, smol, lfm, mistral, phi, internlm, deepseek, yi, other
    static func detect(id: String) -> ModelKind {
        let s = id.lowercased()
        if s.contains("gemma") { return .gemma }
        if s.contains("llama-3") || s.contains("llama3") { return .llama3 }
        // Detect Liquid LFM separately (ChatML with <|startoftext|> prefix)
        if s.contains("lfm2") || s.contains("liquid") { return .lfm }
        // SmolLM models use ChatML with a default system prompt; detect separately
        if s.contains("smol") { return .smol }
        // Map specific families explicitly so we can build family-specific prompts
        if s.contains("internlm") { return .internlm }
        if s.contains("deepseek") { return .deepseek }
        if s.contains("yi") { return .yi }
        // Map other ChatML-adopting families to .qwen (ChatML): Qwen, MPT
        if s.contains("qwen") || s.contains("mpt") {
            return .qwen
        }
        // Llama 2 family uses [INST] with <<SYS>> inside first block
        if s.contains("llama-2") || s.contains("llama2") { return .mistral }
        if s.contains("mistral") || s.contains("mixtral") { return .mistral }
        if s.contains("phi-3") || s.contains("phi3") { return .phi }
        return .other
    }
}

enum RunPurpose { case chat, title }

// MARK: –– Model metadata ----------------------------------------------------
#if canImport(UIKit) || canImport(AppKit)
private enum ModelInfo {
    static let repoID   = "ggml-org/Qwen3-1.7B-GGUF"
    static let fileName = "Qwen3-1.7B-Q4_K_M.gguf"

    /// Returns <Documents>/LocalLLMModels/qwen/Qwen3-1.7B-GGUF/…/Qwen3‑1.7B‑Q4_K_M.gguf
    static func sandboxURL() -> URL {
        var url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalLLMModels", isDirectory: true)
        for comp in repoID.split(separator: "/") {
            url.appendPathComponent(String(comp), isDirectory: true)
        }
        return url.appendingPathComponent(fileName)
    }
}


// MARK: –– One‑shot downloader ----------------------------------------------
@MainActor final class ModelDownloader: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(Double)   // 0…1
        case finished
        case failed(String)
    }

    @Published var state: State = .idle
    @AppStorage("verboseLogging") private var verboseLogging = false

    /// Additional files some models may ship alongside the GGUF.
    /// These are optional so the downloader succeeds even if they are absent.
    private static let extraFiles: [String] = []
    private var fractions: [Double] = []

    init() {
        let modelOK  = FileManager.default.fileExists(atPath: ModelInfo.sandboxURL().path)
        let sideOK   = Self.extraFiles.allSatisfy { name in
            FileManager.default.fileExists(atPath: ModelInfo.sandboxURL()
                .deletingLastPathComponent()
                .appendingPathComponent(name).path)
        }
        state = (modelOK && sideOK) ? .finished : .idle
        if verboseLogging { print("[Downloader] init → state = \(state)") }
        // Startup diagnostics for Metal kernels
        if verboseLogging {
            if let metallib = Bundle.main.path(forResource: "default", ofType: "metallib") {
                print("[Startup] default.metallib found: \(metallib)")
            } else {
                print("[Startup] Warning: default.metallib not found. GPU will be disabled and CPU fallback used.")
            }
        }
    }

    func start() {
        guard state == .idle || state.isFailed else { return }
        if verboseLogging { print("[Downloader] starting…") }
        state = .downloading(0)

        let llmDir   = ModelInfo.sandboxURL().deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: llmDir, withIntermediateDirectories: true)
        } catch {
            state = .failed("mkdir: \(error.localizedDescription)")
            return
        }

        var items: [(repo: String, file: String, dest: URL)] = []
        items.append((ModelInfo.repoID, ModelInfo.fileName, llmDir.appendingPathComponent(ModelInfo.fileName)))
        items += Self.extraFiles.map { (ModelInfo.repoID, $0, llmDir.appendingPathComponent($0)) }

        let total = Double(items.count)
        fractions = Array(repeating: 0.0, count: items.count)

        Task {
            for (idx, item) in items.enumerated() {
                // '?download=1' ensures Hugging Face serves the raw file directly
                let remote  = URL(string: "https://huggingface.co/\(item.repo)/resolve/main/\(item.file)?download=1")!
                let dest    = item.dest

                if verboseLogging { print("[Downloader] ▶︎ \(item.file)") }
                do {
                    try await BackgroundDownloadManager.shared.download(from: remote, to: dest) { part in
                        Task { @MainActor in
                            self.fractions[idx] = part
                            if self.state.isDownloading {
                                self.state = .downloading(self.fractions.reduce(0, +) / total)
                            }
                        }
                    }
                    await MainActor.run {
                        if verboseLogging { print("[Downloader] ✓ \(item.file)") }
                    }
                } catch {
                    await MainActor.run {
                        self.state = .failed(error.localizedDescription)
                        if verboseLogging { print("[Downloader] ❌ \(item.file): \(error.localizedDescription)") }
                    }
                    return
                }
            }

            await MainActor.run {
                self.state = .finished
                if verboseLogging { print("[Downloader] all files done ✅") }
            }
        }
    }
}

private extension ModelDownloader.State {
    var isFailed: Bool       { if case .failed = self { true } else { false } }
    var isDownloading: Bool  { if case .downloading = self { true } else { false } }
}
#endif

// MARK: –– FileManager helpers ----------------------------------------------
extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) { try removeItem(at: url) }
    }
    @discardableResult
    func moveItemReplacing(at dest: URL, from src: URL) throws -> URL {
        try removeItemIfExists(at: dest)
        try moveItem(at: src, to: dest)
        return dest
    }
}

// MARK: –– Download screen ---------------------------------------------------
#if canImport(UIKit) || os(macOS)
struct DownloadView: View {
    @ObservedObject var vm: ModelDownloader

    var body: some View {
        VStack(spacing: 20) {
            Text(LocalizedStringKey("First‑time setup: download the Qwen‑1.7B model and embeddings.\nWi‑Fi recommended."))
                .multilineTextAlignment(.center)

            switch vm.state {
            case .idle:
                Button(LocalizedStringKey("Download Models")) { vm.start() }
                    .buttonStyle(.borderedProminent)

            case .downloading(let p):
                VStack(spacing: 12) {
                    Text(LocalizedStringKey("Downloading…"))
                        .font(.headline)
                    ModernDownloadProgressView(progress: p, speed: nil)
                }

            case .failed(let msg):
                VStack(spacing: 12) {
                    Text("⚠️ " + msg).font(.caption)
                    Button(LocalizedStringKey("Retry")) { vm.start() }
                }

            case .finished:
                ProgressView().progressViewStyle(.circular)
                Text(LocalizedStringKey("Preparing…")).font(.caption)
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
    // Thread-safe store (internally synchronized) is safe to access off the main actor.
    private nonisolated let store: InstalledModelsStore
    @Published var downloadedModels: [LocalModel] = []
    @Published var loadedModel: LocalModel?
    @Published var lastUsedModel: LocalModel?
    @Published var modelSettings: [String: ModelSettings] = [:]
    @Published var downloadedDatasets: [LocalDataset] = []
    @Published var remoteBackends: [RemoteBackend] = []
    @Published var remoteBackendsFetching: Set<RemoteBackend.ID> = []
    @Published var activeRemoteSession: ActiveRemoteSession?
    @Published var activeDataset: LocalDataset?
    @Published var loadingModelName: String?  // Track model name during loading
    private var favouritePaths: [String] = []
    private static let favouriteLimit = 3
    fileprivate var datasetManager: DatasetManager?
    private var cancellables: Set<AnyCancellable> = []
    var activeRelayLANRefreshes: Set<RemoteBackend.ID> = []
    var relayLANRefreshTimestamps: [RemoteBackend.ID: Date] = [:]
    // Track one-time early LAN health probes per backend so we don't spam.
    var lanInitialProbePerformed: Set<RemoteBackend.ID> = []

    init(store: InstalledModelsStore = InstalledModelsStore()) {
        self.store = store
        store.migrateLeapBundles()
        store.migratePaths()
        store.rehomeIfMissing()
        if let fav = UserDefaults.standard.array(forKey: "favouriteModels") as? [String] {
            favouritePaths = Array(fav.prefix(Self.favouriteLimit))
            if favouritePaths.count != fav.count {
                UserDefaults.standard.set(favouritePaths, forKey: "favouriteModels")
            }
        }
        var installed = LocalModel.loadInstalled(store: store)
            .removingDuplicateURLs()
        pruneFavouritePaths(against: installed)
        installed = installed.map { model in
            var m = model
            m.isFavourite = favouritePaths.contains(m.url.path)
            return m
        }
        downloadedModels = installed
        hydrateMoEInfoFromCache()
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
        remoteBackends = RemoteBackendsStore.load()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        scanLayersIfNeeded()
        scanMoEInfoIfNeeded()
    }

    func refresh() {
        store.reload()
        store.migrateLeapBundles()
        store.migratePaths()
        store.rehomeIfMissing()
        var installed = LocalModel.loadInstalled(store: store)
            .removingDuplicateURLs()
        pruneFavouritePaths(against: installed)
        installed = installed.map { model in
            var m = model
            m.isFavourite = favouritePaths.contains(m.url.path)
            return m
        }
        downloadedModels = installed
        hydrateMoEInfoFromCache()
        updateLastUsedModel()
        scanLayersIfNeeded()
        scanMoEInfoIfNeeded()
        scanCapabilitiesIfNeeded()
        datasetManager?.reloadFromDisk()
    }

    // MARK: - Async Refresh (Performance Optimized)

    private var lastRefreshTime: Date = .distantPast
    private static let refreshDebounceInterval: TimeInterval = 0.3

    /// Async version of refresh that moves heavy I/O off the main thread.
    /// Includes debouncing to prevent redundant refreshes when rapidly switching tabs.
    func refreshAsync() async {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshTime) > Self.refreshDebounceInterval else { return }
        lastRefreshTime = now

        // Capture store reference for use in detached task
        let store = self.store
        let currentFavouritePaths = self.favouritePaths

        // Perform heavy I/O operations off the main actor
        let installed = await Task.detached(priority: .userInitiated) {
            store.reload()
            store.migrateLeapBundles()
            store.migratePaths()
            store.rehomeIfMissing()
            var models = LocalModel.loadInstalled(store: store)
                .removingDuplicateURLs()
            models = models.map { model in
                var m = model
                m.isFavourite = currentFavouritePaths.contains(m.url.path)
                return m
            }
            return models
        }.value

        // Update UI on main actor
        pruneFavouritePaths(against: installed)
        downloadedModels = installed
        hydrateMoEInfoFromCache()
        updateLastUsedModel()

        // These already use Task.detached internally
        scanLayersIfNeeded()
        scanMoEInfoIfNeeded()
        scanCapabilitiesIfNeeded()
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
            .receive(on: RunLoop.main)
            .sink { [weak self] ds in
                // Publish changes on the next runloop to avoid nested view-update warnings
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.downloadedDatasets = ds
                    let selectedID = UserDefaults.standard.string(forKey: "selectedDatasetID") ?? ""
                    if selectedID.isEmpty {
                        self.activeDataset = nil
                        return
                    }

                    if let selected = ds.first(where: { $0.datasetID == selectedID }) {
                        // Keep the active dataset object fresh (e.g., when indexing flips isIndexed).
                        self.activeDataset = selected
                    } else {
                        // Selected dataset no longer exists on disk.
                        self.activeDataset = nil
                        UserDefaults.standard.set("", forKey: "selectedDatasetID")
                    }
                }
            }
            .store(in: &cancellables)
    }

    func setActiveDataset(_ ds: LocalDataset?) {
        datasetManager?.select(ds)
        // Defer publishing selection to avoid modifying state during view updates
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeDataset = ds
            let id = ds?.datasetID ?? ""
            UserDefaults.standard.set(id, forKey: "selectedDatasetID")
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
        Task {
            await MoEDetectionStore.shared.remove(modelID: model.modelID, quantLabel: model.quant)
        }
        refresh()
        if loadedModel?.id == model.id { loadedModel = nil }
        if lastUsedModel?.id == model.id { lastUsedModel = nil }
        StartupPreferencesStore.clearLocalPath(model.url.path)
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

    var favouriteCount: Int { favouritePaths.count }
    var favouriteCapacity: Int { Self.favouriteLimit }

    private func persistFavourites() {
        if favouritePaths.count > Self.favouriteLimit {
            favouritePaths = Array(favouritePaths.prefix(Self.favouriteLimit))
        }
        UserDefaults.standard.set(favouritePaths, forKey: "favouriteModels")
    }

    @discardableResult
    private func pruneFavouritePaths(against models: [LocalModel]) -> Bool {
        let validPaths = Set(models.map { $0.url.path })
        let filtered = favouritePaths.filter { validPaths.contains($0) }
        guard filtered != favouritePaths else { return false }
        favouritePaths = filtered
        persistFavourites()
        return true
    }

    func canFavourite(_ model: LocalModel) -> Bool {
        _ = pruneFavouritePaths(against: downloadedModels)
        return favouritePaths.contains(model.url.path) || favouritePaths.count < Self.favouriteLimit
    }

    @discardableResult
    func setFavourite(_ model: LocalModel, isFavourite desired: Bool) -> Bool {
        _ = pruneFavouritePaths(against: downloadedModels)
        let path = model.url.path
        if desired {
            if !favouritePaths.contains(path) {
                guard favouritePaths.count < Self.favouriteLimit else { return false }
                favouritePaths.append(path)
            }
        } else {
            favouritePaths.removeAll { $0 == path }
        }
        persistFavourites()

        let updatedValue = favouritePaths.contains(path)
        if let idx = downloadedModels.firstIndex(where: { $0.id == model.id }) {
            var models = downloadedModels
            models[idx].isFavourite = updatedValue
            downloadedModels = models
        }
        store.updateFavorite(modelID: model.modelID, quantLabel: model.quant, fav: updatedValue)
        return true
    }

    @discardableResult
    func toggleFavourite(_ model: LocalModel) -> Bool {
        _ = pruneFavouritePaths(against: downloadedModels)
        let shouldFavourite = !favouritePaths.contains(model.url.path)
        if shouldFavourite && favouritePaths.count >= Self.favouriteLimit {
            return false
        }
        return setFavourite(model, isFavourite: shouldFavourite)
    }

    func favouriteModels(limit: Int = AppModelManager.favouriteLimit) -> [LocalModel] {
        let favourites = downloadedModels
            .filter { favouritePaths.contains($0.url.path) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastUsedDate ?? lhs.downloadDate
                let rhsDate = rhs.lastUsedDate ?? rhs.downloadDate
                return lhsDate > rhsDate
            }
        return limit > 0 ? Array(favourites.prefix(limit)) : favourites
    }

    func recentModels(limit: Int = 3, excludingIDs: Set<String> = []) -> [LocalModel] {
        let recents = downloadedModels
            .filter { $0.lastUsedDate != nil }
            .filter { !excludingIDs.contains($0.id) }
            .sorted { ($0.lastUsedDate ?? Date.distantPast) > ($1.lastUsedDate ?? Date.distantPast) }
        return limit > 0 ? Array(recents.prefix(limit)) : recents
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

    private func scanMoEInfoIfNeeded() {
        let pending = downloadedModels.filter { model in
            switch model.format {
            case .gguf:
                guard let info = model.moeInfo else { return true }
                if info.isMoE {
                    return info.moeLayerCount == nil || info.totalLayerCount == nil || info.hiddenSize == nil || info.feedForwardSize == nil || info.vocabSize == nil
                }
                return info.totalLayerCount == nil
            case .mlx:
                guard let info = model.moeInfo else { return true }
                if info.isMoE {
                    return info.expertCount <= 1
                }
                if info.totalLayerCount == nil, info.moeLayerCount == 0 {
                    return true
                }
                return false
            case .slm, .apple:
                return false
            }
        }
        guard !pending.isEmpty else { return }
        let models = pending
        Task.detached(priority: .utility) { [weak self] in
            print("[MoEDetect] queued \(models.count) models for metadata scan")
            for model in models {
                let descriptor = "\(model.name) (\(model.quant)) [\(model.format.rawValue)]"
                print("[MoEDetect] ▶︎ scanning \(descriptor)")
                let info = ModelScanner.moeInfo(for: model.url, format: model.format)
                let resolvedInfo: MoEInfo
                if let info {
                    let label = info.isMoE ? "MoE" : "Dense"
                    let moeLayers = info.moeLayerCount.map(String.init) ?? "n/a"
                    let totalLayers = info.totalLayerCount.map(String.init) ?? "n/a"
                    print("[MoEDetect] ✓ \(descriptor) result=\(label) experts=\(info.expertCount) moeLayers=\(moeLayers) totalLayers=\(totalLayers)")
                    resolvedInfo = info
                } else {
                    print("[MoEDetect] ⚠︎ \(descriptor) scan failed; defaulting to Dense metadata")
                    resolvedInfo = .denseFallback
                }
                guard let self else {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    continue
                }
                await self.applyMoEInfo(resolvedInfo, to: model)
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

    private func hydrateMoEInfoFromCache() {
        Task { [weak self] in
            let cache = await MoEDetectionStore.shared.all()
            guard !cache.isEmpty else { return }
            await MainActor.run {
                guard let self else { return }
                var updated = self.downloadedModels
                var mutated = false
                for idx in updated.indices {
                    if updated[idx].moeInfo == nil {
                        let key = MoEDetectionStore.key(modelID: updated[idx].modelID, quantLabel: updated[idx].quant)
                        if let cachedInfo = cache[key] {
                            updated[idx].moeInfo = cachedInfo
                            self.store.updateMoEInfo(modelID: updated[idx].modelID, quantLabel: updated[idx].quant, info: cachedInfo)
                            mutated = true
                        }
                    }
                }
                if mutated {
                    self.downloadedModels = updated
                }
            }
        }
    }

    @MainActor
    private func applyMoEInfo(_ info: MoEInfo, to model: LocalModel) async {
        if let idx = downloadedModels.firstIndex(where: { $0.id == model.id }) {
            downloadedModels[idx].moeInfo = info
        }
        store.updateMoEInfo(modelID: model.modelID, quantLabel: model.quant, info: info)
        await MoEDetectionStore.shared.update(info: info, modelID: model.modelID, quantLabel: model.quant)
    }
}

extension AppModelManager: ModelLoadingManaging {}

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
        var datasetID: String?
        var datasetName: String?
        var perf: Perf?
        var streaming: Bool = false
        // Shows a post-tool-call waiting spinner in the UI until
        // the first continuation token arrives after a tool result.
        var postToolWaiting: Bool = false
        var retrievedContext: String?
        var citations: [Citation]?
        var usedWebSearch: Bool?
        var webHits: [WebHit]?
        var webError: String?
        var imagePaths: [String]?
        var toolCalls: [ToolCall]?

        init(id: UUID = UUID(),
             role: String,
             text: String,
             timestamp: Date = Date(),
             datasetID: String? = nil,
             datasetName: String? = nil,
             perf: Perf? = nil,
             streaming: Bool = false) {
            self.id = id
            self.role = role
            self.text = text
            self.timestamp = timestamp
            self.datasetID = datasetID
            self.datasetName = datasetName
            self.perf = perf
            self.streaming = streaming
        }

        enum CodingKeys: String, CodingKey { case id, role, text, timestamp, datasetID, datasetName, perf, retrievedContext, citations, usedWebSearch, webHits, webError, imagePaths, toolCalls }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            role = try c.decode(String.self, forKey: .role)
            text = try c.decode(String.self, forKey: .text)
            timestamp = (try? c.decode(Date.self, forKey: .timestamp)) ?? Date()
            datasetID = try? c.decode(String.self, forKey: .datasetID)
            datasetName = try? c.decode(String.self, forKey: .datasetName)
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
            try c.encodeIfPresent(datasetID, forKey: .datasetID)
            try c.encodeIfPresent(datasetName, forKey: .datasetName)
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
        case tool(Int) // Index of the tool call in the message's toolCalls array

        var id: UUID { UUID() }

        var isThink: Bool {
            if case .think = self { return true }
            return false
        }

        var isTool: Bool {
            if case .tool = self { return true }
            return false
        }
    }

    enum InjectionStage { case none, deciding, decided, processing, predicting }
    enum InjectionMethod { case full, rag }

    @Published var sessions: [Session] = [] {
        didSet { saveSessions() }
    }
    @Published var activeSessionID: Session.ID? {
        didSet {
            saveSessions()
            // Recreate rolling thought view models when switching sessions
            DispatchQueue.main.async { [weak self] in
                self?.recreateRollingThoughtViewModels()
            }
            if let id = activeSessionID {
                Task { [weak self] in
                    guard let self else { return }
                    await self.remoteService?.updateConversationID(id)
                }
            }
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
    // In-memory thumbnails for pending attachments to avoid re-decoding on each keystroke.
    @Published private(set) var pendingThumbnails: [URL: UIImage] = [:]
    @Published var crossSessionSendBlocked: Bool = false
    @Published var spotlightMessageID: UUID?

    private struct PendingPerfAccumulator {
        var start: Date
        var firstToken: Date?
        var lastToken: Date?
        var tokenCount: Int
    }

    private var pendingPerfAccumulators: [UUID: PendingPerfAccumulator] = [:]

    private func beginPerfTracking(messageID: UUID, start: Date) {
        pendingPerfAccumulators[messageID] = PendingPerfAccumulator(start: start, firstToken: nil, lastToken: nil, tokenCount: 0)
    }

    private func recordToken(messageID: UUID, timestamp: Date = Date()) {
        guard var acc = pendingPerfAccumulators[messageID] else { return }
        acc.tokenCount += 1
        if acc.firstToken == nil {
            acc.firstToken = timestamp
        }
        acc.lastToken = timestamp
        pendingPerfAccumulators[messageID] = acc
    }

    private func finalizePerf(messageID: UUID, injectionOverhead: Int) -> Msg.Perf? {
        guard let acc = pendingPerfAccumulators.removeValue(forKey: messageID),
              let first = acc.firstToken,
              let last = acc.lastToken else { return nil }
        let duration = last.timeIntervalSince(first)
        let rate = duration > 0 ? Double(acc.tokenCount) / duration : 0
        let totalTokens = acc.tokenCount + max(0, injectionOverhead)
        let timeToFirst = first.timeIntervalSince(acc.start)
        return Msg.Perf(tokenCount: totalTokens, avgTokPerSec: rate, timeToFirst: timeToFirst)
    }

    private func cancelPerfTracking(messageID: UUID) {
        pendingPerfAccumulators.removeValue(forKey: messageID)
    }

    private func finalizeAssistantStream(
        runID: Int,
        messageIndex: Int,
        cleanedText: String,
        pendingToolJSON: String?,
        perfResult: Msg.Perf?,
        tokenCount: Int,
        generationStart: Date,
        firstTokenTimestamp: Date?,
        isMLXFormat: Bool
    ) {
        guard runID == activeRunID,
              streamMsgs.indices.contains(messageIndex) else { return }

        let displayText: String
        if cleanedText.isEmpty, pendingToolJSON != nil {
            displayText = ""
        } else {
            displayText = cleanedText.isEmpty ? "(no output)" : cleanedText
        }

        streamMsgs[messageIndex].text = displayText
        streamMsgs[messageIndex].streaming = false
        if let perfResult {
            streamMsgs[messageIndex].perf = perfResult
        }

        if pendingToolJSON == nil {
            AccessibilityAnnouncer.announceLocalized("Response generated.")
            markRollingThoughtsInterrupted(forMessageAt: messageIndex)
        }

        if verboseLogging {
            print("[ChatVM] BOT ✓ \(displayText.prefix(80))…")
        }

        let ttfbStr: String = {
            guard let firstTokenTimestamp else { return "n/a" }
            return String(format: "%.2fs", firstTokenTimestamp.timeIntervalSince(generationStart))
        }()

        let botText = streamMsgs[messageIndex].text
        let logPrefix = "[ChatVM] BOT ✓ tokens=\(tokenCount) ttfb=\(ttfbStr)"
        Task {
            if isMLXFormat {
                let logMessage = "\(logPrefix)\n\(botText)"
                await logger.log(logMessage, truncateConsole: false)
            } else {
                let previewLimit = 120
                let preview = String(botText.prefix(previewLimit))
                let suffix = botText.count > previewLimit ? "…" : ""
                let logMessage = "\(logPrefix) preview=\(preview)\(suffix)"
                await logger.log(logMessage)
            }
        }

        let clearDelay: TimeInterval = 2.0
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(clearDelay * 1_000_000_000))
            if runID == self.activeRunID {
                self.injectionStage = .none
                self.injectionMethod = nil
            }
        }
    }

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
        let shouldIncludeWebGuidance: Bool = {
            if let override = systemPromptWebSearchOverride {
                return override
            }
            return WebToolGate.isAvailable(currentFormat: loadedFormat)
        }()
        let includeThinkRestriction = activeRemoteBackendID == nil
        let attachedCount = supportsImageInput ? pendingImageURLs.count : 0
        let hasAttachedImages = supportsImageInput && attachedCount > 0
        return SystemPromptResolver.general(
            currentFormat: loadedFormat,
            isVisionCapable: supportsImageInput,
            hasAttachedImages: hasAttachedImages,
            attachedImageCount: hasAttachedImages ? attachedCount : nil,
            includeThinkRestriction: includeThinkRestriction,
            webGuidanceOverride: shouldIncludeWebGuidance
        )
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

    var loadedModelURL: URL? { loadedURL }
    var loadedModelSettings: ModelSettings? { loadedSettings }
    var loadedModelFormat: ModelFormat? { loadedFormat }
    private var currentInjectedTokenOverhead: Int = 0

    /// Reference to the global model manager so the chat view model can access
    /// the currently selected dataset for RAG lookups.
    weak var modelManager: AppModelManager?
    /// Dataset manager used to track indexing status while performing
    /// retrieval or injection. Held weakly since it is owned by the
    /// main view hierarchy.
    weak var datasetManager: DatasetManager?

    private var client: AnyLLMClient?
    private var remoteService: RemoteChatService?
    private var activeRemoteBackendID: RemoteBackend.ID?
    private var activeRemoteModelID: String?
    private var remoteLoadingPending = false
    private var toolSpecsCache: [ToolSpec] = []
    private var systemPromptWebSearchOverride: Bool?
    
    @AppStorage("verboseLogging") private var verboseLogging = false
    @AppStorage("ragMaxChunks") private var ragMaxChunks = 5
    @AppStorage("ragMinScore") private var ragMinScore = 0.5

    private var didInjectDataset = false
    private var lastDatasetID: String?

    init() {
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

    func setDatasetForActiveSession(_ ds: LocalDataset?) {
        if ds != nil, isSLMModel {
            Task { await logger.log("[ChatVM] Ignoring dataset assignment because current model is SLM") }
            modelManager?.setActiveDataset(nil)
            return
        }

        modelManager?.setActiveDataset(ds)
        if ds == nil {
            // Reset injection state so subsequent runs don't carry stale dataset flags.
            lastDatasetID = nil
            didInjectDataset = false
            currentInjectedTokenOverhead = 0
        }
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

    var isStreamingInAnotherSession: Bool {
        guard let streamIdx = streamSessionIndex else { return false }
        if let activeIdx = activeIndex, streamIdx == activeIdx { return false }
        guard sessions.indices.contains(streamIdx) else { return false }
        return sessions[streamIdx].messages.last?.streaming == true
    }

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

    func focus(onMessageWithID id: UUID) {
        spotlightMessageID = id
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

    @MainActor
    func resolveLoadURL(for model: LocalModel) -> URL {
        resolveLoadURL(for: model.url, explicitFormat: model.format, modelHint: model).url
    }

    struct PreparedModelLoad {
        let url: URL
        let format: ModelFormat
        let settings: ModelSettings?
    }

    @MainActor
    func resolveLoadURL(
        for originalURL: URL,
        explicitFormat: ModelFormat?,
        modelHint: LocalModel? = nil
    ) -> (url: URL, format: ModelFormat) {
        let detectedFmt = explicitFormat ?? ModelFormat.detect(from: originalURL)
        var loadURL = originalURL

        if detectedFmt == .gguf {
            let quantLabel = QuantExtractor.shortLabel(from: originalURL.lastPathComponent, format: .gguf).lowercased()
            if quantLabel.starts(with: "q") {
                setenv("LLAMA_METAL_KQUANTS", quantLabel, 1)
            } else {
                setenv("LLAMA_METAL_KQUANTS", "", 1)
            }

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDirectory)
            if exists, isDirectory.boolValue, let alt = InstalledModelsStore.firstGGUF(in: loadURL) {
                loadURL = alt
            }

            var effectiveIsDir: ObjCBool = false
            let effectiveExists = FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &effectiveIsDir)
            let isValid = effectiveExists && (effectiveIsDir.boolValue || InstalledModelsStore.isValidGGUF(at: loadURL))
            if !isValid {
                let managerModel = modelManager?.downloadedModels.first(where: { candidate in
                    candidate.url == originalURL
                        || candidate.url == loadURL
                        || candidate.url.deletingLastPathComponent() == originalURL
                        || candidate.url.deletingLastPathComponent() == loadURL
                })
                let modelID = modelHint?.modelID
                    ?? managerModel?.modelID
                    ?? inferRepoID(from: loadURL)
                    ?? loadURL.deletingLastPathComponent().lastPathComponent
                let base = InstalledModelsStore.baseDir(for: .gguf, modelID: modelID)
                if let alt = InstalledModelsStore.firstGGUF(in: base) {
                    loadURL = alt
                }
            }
        } else {
            setenv("LLAMA_METAL_KQUANTS", "", 1)
        }

        return (loadURL, detectedFmt)
    }


    @MainActor
    func prepareLoad(
        for originalURL: URL,
        settings: ModelSettings?,
        format: ModelFormat?,
        modelHint: LocalModel? = nil
    ) async throws -> PreparedModelLoad {
        let resolution = resolveLoadURL(for: originalURL, explicitFormat: format, modelHint: modelHint)
        var loadURL = resolution.url
        let detectedFmt = resolution.format


        guard FileManager.default.fileExists(atPath: loadURL.path) else {
            throw NSError(domain: "Noema", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model not downloaded"])
        }

        var finalSettings = settings

        if detectedFmt == .mlx {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir)
            if !isDir.boolValue {
                let dir = loadURL.deletingLastPathComponent()
                var dirIsDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: dir.path, isDirectory: &dirIsDir), dirIsDir.boolValue {
                    loadURL = dir
                    if verboseLogging { print("[ChatVM] Adjusted MLX URL to directory: \(dir.path)") }
                } else {
                    throw NSError(domain: "Noema", code: 400, userInfo: [NSLocalizedDescriptionKey: "MLX model directory missing"])
                }
            }

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

            do {
                let cfg = loadURL.appendingPathComponent("config.json")
                let data = try Data(contentsOf: cfg)
                _ = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw NSError(domain: "Noema", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid or missing config.json in MLX model directory"])
            }

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
            if (finalSettings?.tokenizerPath ?? "").isEmpty {
                if let first = possibleTokenizers
                    .map({ loadURL.appendingPathComponent($0) })
                    .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    var s = finalSettings ?? ModelSettings.default(for: .mlx)
                    s.tokenizerPath = first.path
                    finalSettings = s
                }
            }
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
                if var s = finalSettings {
                    let layers = ModelScanner.layerCount(for: loadURL, format: .gguf)
                    let ctxMax = GGUFMetadata.contextLength(at: loadURL) ?? Int.max
                    if s.gpuLayers >= 0, layers > 0 {
                        // Only clamp when layer count is known; otherwise trust the user's value
                        s.gpuLayers = min(max(0, s.gpuLayers), layers)
                    }
                    s.contextLength = min(s.contextLength, Double(ctxMax))
                    if (s.tokenizerPath ?? "").isEmpty {
                        var isDir: ObjCBool = false
                        var modelDir = loadURL.deletingLastPathComponent()
                        if FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir), isDir.boolValue {
                            modelDir = loadURL
                        }
                        let tok = modelDir.appendingPathComponent("tokenizer.json")
                        if FileManager.default.fileExists(atPath: tok.path) {
                            s.tokenizerPath = tok.path
                        }
                    }
                    finalSettings = s
                }
            case .slm, .apple:
                break
            }
        }

        if let s = finalSettings, detectedFmt == .gguf {
            applyEnvironmentVariables(from: s)
        }

        return PreparedModelLoad(url: loadURL, format: detectedFmt, settings: finalSettings)
    }

    private func ensureClient(
        url: URL,
        settings: ModelSettings?,
        format: ModelFormat?,
        forceReload: Bool
    ) async throws {
        if client != nil {
            guard forceReload else { return }
            // Fully unload the existing runner before starting a new load to avoid
            // llama.cpp/Metal races on iOS when models are reloaded back‑to‑back.
            await unload()
        }
        // Reset any prior loopback server and vision override. The newly selected model
        // will explicitly re-enable and restart the server if needed.
        LlamaServerBridge.stop()
        // Reset loopback vision override; the new selection will explicitly re-enable it if needed.
        UserDefaults.standard.set(false, forKey: "serverVisionEnabled")
        loading = true
        stillLoading = false
        loadError = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.loading == true { self?.stillLoading = true }
        }
        defer { loading = false; stillLoading = false }

        let prepared = try await prepareLoad(for: url, settings: settings, format: format)
        var loadURL = prepared.url
        let detectedFmt = prepared.format
        var finalSettings = prepared.settings

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64 {
            let sizeGB = Double(size) / 1_073_741_824.0
            let text = DeviceRAMInfo.current().limit
            if let num = Double(text.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)),
               sizeGB > num {
                loadError = "Model may exceed available RAM (\(String(format: "%.1f", sizeGB)) GB > \(text))"
            }
        }
        if let s = finalSettings {
            if verboseLogging { print("[ChatVM] loading \(loadURL.lastPathComponent) with context \(Int(s.contextLength))") }
        } else {
            if verboseLogging {
                let kind = detectedFmt == .gguf ? "GGUF" : (detectedFmt == .mlx ? "MLX" : "SLM")
                print("[ChatVM] loading \(kind) from \(loadURL.lastPathComponent)…")
            }
        }
        if verboseLogging { print("MODEL_LOAD_START \(Date().timeIntervalSince1970)") }

        let llamaOptions = LlamaOptions(extraEOSTokens: ["<|im_end|>", "<end_of_turn>"], verbose: true)
        let contextOverride = finalSettings.map { settings -> Int in
            let clamped = max(1.0, min(settings.contextLength, Double(Int32.max)))
            return Int(clamped)
        }
        let threadOverride = finalSettings.map { settings -> Int in
            let requested = settings.cpuThreads > 0 ? settings.cpuThreads : ProcessInfo.processInfo.activeProcessorCount
            return max(1, requested)
        }
        // Resolve projector info next to the model (if any). If the model is
        // vision-capable (merged projector or external mmproj), start the
        // in‑process HTTP server bound to 127.0.0.1 so multimodal requests
        // consistently route via loopback.
        let explicitMMProj: String? = ProjectorLocator.projectorPath(alongside: loadURL)
        let hasMergedProjector: Bool = (detectedFmt == .gguf) ? GGUFMetadata.hasMultimodalProjector(at: loadURL) : false
        if detectedFmt == .gguf, (explicitMMProj != nil || hasMergedProjector) {
            // Capture only Sendable values before launching the detached task.
            let loadPath = loadURL.path
            let mmprojPath = explicitMMProj
            // Ensure we are restarting the server for the newly selected model.
            // Run on a detached task to avoid blocking the main thread (which freezes the loading UI).
            let p = await Task.detached { @Sendable () -> Int32 in
                LlamaServerBridge.stop()
                return LlamaServerBridge.start(
                    host: "127.0.0.1",
                    preferredPort: 0,
                    ggufPath: loadPath,
                    mmprojPath: mmprojPath
                )
            }.value

            if p > 0 {
                let d = UserDefaults.standard
                d.set(true, forKey: "serverVisionEnabled")
                d.synchronize()
                let projName = explicitMMProj.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "merged"
                if verboseLogging { print("[ChatVM] Started loopback llama.cpp server on 127.0.0.1:\(p) with projector \(projName)") }
                Task { await logger.log("[Loopback] start host=127.0.0.1 port=\(p) gguf=\(loadURL.lastPathComponent) mmproj=\(projName)") }
            } else {
                if verboseLogging { print("[ChatVM] Failed to start loopback llama.cpp server; continuing without vision server") }
                Task { await logger.log("[Loopback] start.failed gguf=\(loadURL.lastPathComponent) mmproj=\(explicitMMProj.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "merged")") }
            }
        }
        let llamaParameter = LlamaParameter(
            options: llamaOptions,
            contextLength: contextOverride,
            threadCount: threadOverride,
            mmproj: explicitMMProj
        )

        if let f = format {
            switch f {
            case .mlx:
                print("[ChatVM] MLX load start: \(loadURL.path)")
                SettingsStore.shared.webSearchArmed = false
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
                        parameter: llamaParameter
                    )
                )
                loadedFormat = .gguf
            case .slm:
#if canImport(LeapSDK)
                // Disarm web search before activating Leap SLM so no tools register
                SettingsStore.shared.webSearchArmed = false
                LeapBundleDownloader.sanitizeBundleIfNeeded(at: loadURL)
                let runner = try await Leap.load(url: loadURL)
                let ident = loadURL.deletingPathExtension().lastPathComponent
                // Do not inject a system prompt for SLM models; let them run normally
                let leapClient = LeapLLMClient.make(runner: runner, modelIdentifier: ident)
                client = try await AnyLLMClient(leapClient)
                loadedFormat = .slm
                // Datasets are not supported with SLM models – clear any active selection
                if modelManager?.activeDataset != nil { setDatasetForActiveSession(nil) }
#else
                throw NSError(
                    domain: "Noema",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(
                            localized: "SLM models are not supported on this platform.",
                            locale: LocalizationManager.preferredLocale()
                        )
                    ]
                )
#endif
            case .apple:
                throw NSError(
                    domain: "Noema",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(
                            localized: "Unsupported model format",
                            locale: LocalizationManager.preferredLocale()
                        )
                    ]
                ) 
            }
        } else {
            // Auto-detect format and load via appropriate client
            let detected = ModelFormat.detect(from: loadURL)
            switch detected {
            case .mlx:
                print("[ChatVM] MLX load start: \(loadURL.path)")
                SettingsStore.shared.webSearchArmed = false
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
                        parameter: llamaParameter
                    )
                )
                loadedFormat = .gguf
            case .slm:
#if canImport(LeapSDK)
                LeapBundleDownloader.sanitizeBundleIfNeeded(at: loadURL)
                let runner = try await Leap.load(url: loadURL)
                let ident = loadURL.deletingPathExtension().lastPathComponent
                // Do not inject a system prompt for SLM models; let them run normally
                let leapClient = LeapLLMClient.make(runner: runner, modelIdentifier: ident)
                client = try await AnyLLMClient(leapClient)
                loadedFormat = .slm
                // Datasets are not supported with SLM models – clear any active selection
                if modelManager?.activeDataset != nil { setDatasetForActiveSession(nil) }
#else
                throw NSError(
                    domain: "Noema",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(
                            localized: "SLM models are not supported on this platform.",
                            locale: LocalizationManager.preferredLocale()
                        )
                    ]
                )
#endif
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
        AccessibilityAnnouncer.announceLocalized("Model loaded.")

        // Update image-input capability from stored metadata; fallback to local detection when unknown
        var imageDetectNotes: [String] = []
        if let loadedModel = modelManager?.downloadedModels.first(where: { $0.url == loadURL }) {
            supportsImageInput = loadedModel.isMultimodal
            imageDetectNotes.append("store.isMultimodal=\(loadedModel.isMultimodal)")
        } else {
            supportsImageInput = false
            imageDetectNotes.append("store.missing")
        }
        if supportsImageInput == false {
            // Heuristic fallback by format to ensure the image button appears when applicable
            if let fmt = loadedFormat {
                switch fmt {
                case .gguf:
                    let guess = Self.guessLlamaVisionModel(from: loadURL)
                    supportsImageInput = guess
                    imageDetectNotes.append("gguf.heuristic=\(guess)")
                case .mlx:
                    let isVLM = MLXBridge.isVLMModel(at: loadURL)
                    supportsImageInput = isVLM
                    imageDetectNotes.append("mlx.isVLM=\(isVLM)")
                case .slm:
#if canImport(LeapSDK)
                    // Prefer Leap catalog slug heuristic; fallback to bundle scan when available
                    let slug = loadURL.deletingPathExtension().lastPathComponent
                    let isVision = LeapCatalogService.isVisionQuantizationSlug(slug) || LeapCatalogService.bundleLikelyVision(at: loadURL)
                    supportsImageInput = isVision
                    imageDetectNotes.append("slm.catalogOrBundle=\(isVision)")
#else
                    supportsImageInput = false
#endif
                case .apple:
                    break
                }
                // Persist capability if newly detected
                if supportsImageInput, let manager = modelManager,
                   let model = manager.downloadedModels.first(where: { $0.url == loadURL }) {
                    manager.setCapabilities(modelID: model.modelID, quant: model.quant, isMultimodal: true, isToolCapable: model.isToolCapable)
                    imageDetectNotes.append("persisted=true")
                }
            }
        }
        // Finally, intersect with the runtime compiler capability so UI never advertises
        // image input when the llama.cpp build lacks llava/clip. If headers are hidden but
        // symbols exist (common with some XCFrameworks), prefer a runtime symbol check.
        if loadedFormat == .gguf {
            let d = UserDefaults.standard
            var compiled = d.bool(forKey: "llama.compiledVision")
            if compiled == false {
                // Soft fallback: if the binary contains the necessary symbols, treat as compiled.
                if LlamaRunner.runtimeHasVisionSymbols() {
                    compiled = true
                    imageDetectNotes.append("runtimeSymbols=true")
                }
            }
            if compiled == false {
                // If the in-process server is armed with a projector, allow image UI even when the
                // embedded xcframework lacks vision entry points.
                if d.bool(forKey: "serverVisionEnabled") {
                    supportsImageInput = true
                    imageDetectNotes.append("serverVision=true")
                } else {
                    supportsImageInput = false
                    imageDetectNotes.append("build.compiledVision=false")
                }
            } else {
                // Only hide due to probe if we truly lack a projector. Some builds cannot run our
                // probe despite having vision; in that case, presence of a projector or merged VLM
                // is sufficient to surface the button.
                let probe = d.string(forKey: "llama.visionProbe")
                let hasProj = (ProjectorLocator.projectorPath(alongside: loadURL) != nil) || GGUFMetadata.hasMultimodalProjector(at: loadURL)
                if let probe, probe != "OK", hasProj == false {
                    supportsImageInput = false
                    imageDetectNotes.append("build.probe=\(probe)")
                }
            }
            // Final override: if the server indicates vision support, prefer enabling UI controls
            if d.bool(forKey: "serverVisionEnabled") { supportsImageInput = true }
        }
        Task { await logger.log("[Images][Capability] format=\(String(describing: loadedFormat)) supports=\(supportsImageInput) notes=\(imageDetectNotes.joined(separator: ","))") }

        // Persist current model format and function-calling capability for tool gating (e.g., web search)
        do {
            let d = UserDefaults.standard
            if let fmt = loadedFormat { d.set(fmt.rawValue, forKey: "currentModelFormat") }
            d.set(false, forKey: "currentModelIsRemote")
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
        let supportsOffload = DeviceGPUInfo.supportsGPUOffload
        // If sentinel (-1): request all available GPU layers by using a large value (clamped by backend)
        let resolvedGpuLayers: Int = {
            guard supportsOffload else { return 0 }
            if s.gpuLayers < 0 { return 1_000_000 }
            return max(0, s.gpuLayers)
        }()
        setenv("LLAMA_N_GPU_LAYERS", String(resolvedGpuLayers), 1)
        let threadCount = s.cpuThreads > 0 ? s.cpuThreads : ProcessInfo.processInfo.activeProcessorCount
        let clampedThreads = max(1, threadCount)
        setenv("LLAMA_THREADS", String(clampedThreads), 1)
        setenv("LLAMA_THREADS_BATCH", String(clampedThreads), 1)
        // Some llama/ggml builds still honor GGML_* env names – set both for safety
        setenv("GGML_NUM_THREADS", String(clampedThreads), 1)
        setenv("GGML_NUM_THREADS_BATCH", String(clampedThreads), 1)
        let kvOffloadEnabled = supportsOffload && resolvedGpuLayers > 0 && s.kvCacheOffload
        setenv("LLAMA_KV_OFFLOAD", kvOffloadEnabled ? "1" : "0", 1)
        setenv("LLAMA_MMAP", s.useMmap ? "1" : "0", 1)
        setenv("LLAMA_KEEP", s.keepInMemory ? "1" : "0", 1)
        if let seed = s.seed {
            setenv("LLAMA_SEED", String(seed), 1)
        } else {
            // Do not set a persistent seed here; session start will set a random seed per session
            unsetenv("LLAMA_SEED")
        }
        if s.flashAttention {
            setenv("LLAMA_FLASH_ATTENTION", "1", 1)
            setenv("LLAMA_V_QUANT", s.vCacheQuant.rawValue, 1)
        } else {
            setenv("LLAMA_FLASH_ATTENTION", "0", 1)
            unsetenv("LLAMA_V_QUANT")
        }
        setenv("LLAMA_K_QUANT", s.kCacheQuant.rawValue, 1)
        if let tok = s.tokenizerPath { setenv("LLAMA_TOKENIZER_PATH", tok, 1) }
        if let experts = s.moeActiveExperts, experts > 0 {
            setenv("LLAMA_MOE_EXPERTS", String(experts), 1)
        } else {
            unsetenv("LLAMA_MOE_EXPERTS")
        }
        setenv("NOEMA_TEMPERATURE", String(format: "%.3f", s.temperature), 1)
        setenv("NOEMA_TOP_K", String(max(1, s.topK)), 1)
        setenv("NOEMA_TOP_P", String(format: "%.3f", s.topP), 1)
        setenv("NOEMA_MIN_P", String(format: "%.3f", s.minP), 1)
        setenv("NOEMA_REPEAT_PENALTY", String(format: "%.3f", s.repetitionPenalty), 1)
        setenv("NOEMA_REPEAT_LAST_N", String(max(0, s.repeatLastN)), 1)
        setenv("NOEMA_PRESENCE_PENALTY", String(format: "%.3f", s.presencePenalty), 1)
        setenv("NOEMA_FREQUENCY_PENALTY", String(format: "%.3f", s.frequencyPenalty), 1)
        if let rope = s.ropeScaling {
            setenv("NOEMA_ROPE_SCALING", "yarn", 1)
            setenv("NOEMA_ROPE_FACTOR", String(format: "%.3f", rope.factor), 1)
            setenv("NOEMA_ROPE_BASE", String(rope.originalContext), 1)
            setenv("NOEMA_ROPE_LOW_FREQ", String(format: "%.3f", rope.lowFrequency), 1)
            setenv("NOEMA_ROPE_HIGH_FREQ", String(format: "%.3f", rope.highFrequency), 1)
        } else {
            unsetenv("NOEMA_ROPE_SCALING")
            unsetenv("NOEMA_ROPE_FACTOR")
            unsetenv("NOEMA_ROPE_BASE")
            unsetenv("NOEMA_ROPE_LOW_FREQ")
            unsetenv("NOEMA_ROPE_HIGH_FREQ")
        }
        if !s.logitBias.isEmpty,
           let data = try? JSONEncoder().encode(s.logitBias),
           let json = String(data: data, encoding: .utf8) {
            setenv("NOEMA_LOGIT_BIAS", json, 1)
        } else {
            unsetenv("NOEMA_LOGIT_BIAS")
        }
        if s.promptCacheEnabled {
            setenv("NOEMA_PROMPT_CACHE", s.promptCachePath, 1)
            setenv("NOEMA_PROMPT_CACHE_ALL", s.promptCacheAll ? "1" : "0", 1)
        } else {
            unsetenv("NOEMA_PROMPT_CACHE")
            unsetenv("NOEMA_PROMPT_CACHE_ALL")
        }
        if let overrideValue = s.tensorOverride.overrideValue {
            setenv("NOEMA_OVERRIDE_TENSOR", overrideValue, 1)
        } else {
            unsetenv("NOEMA_OVERRIDE_TENSOR")
        }
        // Speculative decoding environment variables are not applied on macOS.
        #if !os(macOS)
        if let helper = s.speculativeDecoding.helperModelID, !helper.isEmpty {
            setenv("NOEMA_DRAFT_MODEL", helper, 1)
            let mode = s.speculativeDecoding.mode == .tokens ? "tokens" : "max"
            setenv("NOEMA_DRAFT_MODE", mode, 1)
            setenv("NOEMA_DRAFT_VALUE", String(max(1, s.speculativeDecoding.value)), 1)
            if let manager = modelManager,
               let candidate = manager.downloadedModels.first(where: { $0.modelID == helper }) {
                setenv("NOEMA_DRAFT_PATH", candidate.url.path, 1)
            } else {
                unsetenv("NOEMA_DRAFT_PATH")
            }
        } else {
            unsetenv("NOEMA_DRAFT_MODEL")
            unsetenv("NOEMA_DRAFT_MODE")
            unsetenv("NOEMA_DRAFT_VALUE")
            unsetenv("NOEMA_DRAFT_PATH")
        }
        #else
        unsetenv("NOEMA_DRAFT_MODEL")
        unsetenv("NOEMA_DRAFT_MODE")
        unsetenv("NOEMA_DRAFT_VALUE")
        unsetenv("NOEMA_DRAFT_PATH")
        #endif
    }

    func load(
        url: URL,
        settings: ModelSettings? = nil,
        format: ModelFormat? = nil,
        forceReload: Bool = false
    ) async -> Bool {
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
            try await ensureClient(url: url, settings: settings, format: fmt, forceReload: forceReload)
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

    func activeClientForBenchmark() throws -> AnyLLMClient {
        guard let client else {
            throw NSError(domain: "Noema", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model client is not ready"])
        }
        return client
    }

    func makeBenchmarkInput(from rawPrompt: String) -> LLMInput {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        #if canImport(LeapSDK)
        if loadedFormat == .slm {
            let userMessage = ChatMessage(role: "user", content: prompt)
            return LLMInput(.messages([userMessage]))
        }
        #endif

        let history: [Msg] = [Msg(role: "🧑‍💻", text: prompt, timestamp: Date())]
        let systemPrompt = systemPromptText
        Task {
            await logger.log("[ChatVM] SYSTEM PROMPT\n\(systemPrompt)")
        }
        let rendered = prepareForGeneration(messages: history, system: systemPrompt)
        switch rendered {
        case .messages(let messages):
            let chatMessages = messages.map { ChatMessage(role: $0.role, content: $0.content) }
            return LLMInput(.messages(chatMessages))
        case .plain(let text):
            return LLMInput(.plain(text))
        }
    }

    nonisolated static func guessLlamaVisionModel(from url: URL) -> Bool {
        ModelVisionDetector.guessLlamaVisionModel(from: url)
    }

    private func unloadResources() {
        // Ensure any in-flight loading HUD stops immediately when unloading/ejecting
        if loading {
            loading = false
        } else {
            loadingProgressTracker.completeLoading()
        }
        stillLoading = false

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

        if let service = remoteService {
            Task {
                await service.setTransportObserver(nil)
#if os(iOS) || os(visionOS)
                await service.setLANRefreshHandler(nil)
#endif
                await service.cancelActiveStream()
            }
        }
        remoteService = nil
        systemPromptWebSearchOverride = nil
        if activeRemoteBackendID != nil {
            modelManager?.activeRemoteSession = nil
        }
        activeRemoteBackendID = nil
        activeRemoteModelID = nil
        remoteLoadingPending = false
        UserDefaults.standard.set(false, forKey: "currentModelIsRemote")

        client?.unload()
        client = nil
        modelLoaded = false
        loadedURL = nil
        loadedSettings = nil
        loadedFormat = nil
    }

    private func fetchToolSpecs() async -> [ToolSpec] {
        if !toolSpecsCache.isEmpty { return toolSpecsCache }
        await ToolRegistrar.shared.initializeTools()
        let specs = await MainActor.run { () -> [ToolSpec] in
            (try? ToolRegistry.shared.generateToolSpecs()) ?? []
        }
        toolSpecsCache = specs
        return specs
    }

    nonisolated func unload() async {
        // Capture the current client so we can await a full teardown off the main actor.
        let clientToUnload: AnyLLMClient? = await MainActor.run { () -> AnyLLMClient? in
            let captured = self.client
            // Perform UI + state teardown immediately
            self.unloadResources()
            return captured
        }
        // If the client supports an awaited unload, use it to ensure memory is freed.
        if let c = clientToUnload {
            await c.unloadAndWait()
        }
    }

#if canImport(LeapSDK)
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
            AccessibilityAnnouncer.announceLocalized("Model loaded.")
        } catch {
            client = nil
            modelLoaded = false
        }
    }
#endif

    func activateRemoteSession(backend: RemoteBackend, model: RemoteModel) async throws {
        if !backend.isCloudRelay {
            guard backend.chatEndpointURL != nil else {
                throw RemoteBackendError.invalidEndpoint
            }
        }
        let modelIdentifier = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelIdentifier.isEmpty else {
            throw RemoteBackendError.validationFailed("Model identifier missing.")
        }

        systemPromptWebSearchOverride = nil

        unloadResources()

        // Do NOT clear active dataset when switching to a remote session.
        // RAG injection works with remote backends; keep the user's selection.

        let specs = await fetchToolSpecs()
        toolSpecsCache = specs

        let service = RemoteChatService(backend: backend, modelID: modelIdentifier, toolSpecs: specs)
        remoteService = service
        let backendID = backend.id
        await service.setTransportObserver { [weak self] transport, streaming in
            await MainActor.run {
                guard let self else { return }
                self.updateActiveRemoteTransport(for: backendID, transport: transport, streaming: streaming)
            }
        }
#if os(iOS) || os(visionOS)
        await service.setLANRefreshHandler { [weak self] in
            guard let self else { return nil }
            return await self.refreshRelayBackend(backendID: backendID)
        }
#endif
        // Preflight LAN adoption (iOS/visionOS) before establishing UI session state
        var initialLANSSID: String? = nil
#if os(iOS) || os(visionOS)
        initialLANSSID = await service.preflightLANAdoption()
#endif

        activeRemoteBackendID = backend.id
        activeRemoteModelID = modelIdentifier

        do {
        if backend.endpointType == .noemaRelay {
            let containerID = backend.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !containerID.isEmpty else {
                throw RemoteBackendError.validationFailed("Missing CloudKit container identifier for relay.")
            }
            guard let hostDeviceID = backend.relayHostDeviceID?.trimmingCharacters(in: .whitespacesAndNewlines), !hostDeviceID.isEmpty else {
                throw RemoteBackendError.validationFailed("Missing host device ID for relay.")
            }
            let recordName: String
            if let relayRecord = model.relayRecordName, !relayRecord.isEmpty {
                recordName = relayRecord
            } else if modelIdentifier.hasPrefix("model-") {
                recordName = modelIdentifier
            } else {
                recordName = "model-\(modelIdentifier)"
            }
            let payload: [String: Any] = [
                "modelRef": recordName,
                "ensure": "loaded"
            ]
            let body = try JSONSerialization.data(withJSONObject: payload, options: [])
            let command = try await RelayCatalogClient.shared.createCommand(
                containerIdentifier: containerID,
                hostDeviceID: hostDeviceID,
                verb: "POST",
                path: "/models/activate",
                body: body
            )
            let result = try await RelayCatalogClient.shared.waitForCommand(
                containerIdentifier: containerID,
                commandID: command.recordID,
                // Don't block the UI for minutes. Wait briefly and then
                // allow streaming to proceed; the Mac can finish activation
                // in the background.
                timeout: 25
            )
            if result.state != .succeeded {
                if let data = result.result,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["error"] as? String {
                    throw RemoteBackendError.validationFailed(message)
                }
                throw RemoteBackendError.validationFailed("Relay activation failed.")
            }
        } } catch let relayError as RelayError {
            if case .timeout = relayError {
                // Continue without failing; first message will proceed once the
                // Mac finishes activation. This avoids indefinite spinners.
                await logger.log("[RemoteBackendAPI] ⚠️ Relay activation timed out; continuing without blocking UI.")
            } else {
                throw relayError
            }
        }

        await service.updateConversationID(activeSessionID)
        if backend.endpointType == .noemaRelay {
            await service.updateRelayContainerID(backend.baseURLString)
        } else if backend.endpointType == .cloudRelay {
            let containerID = RelayConfiguration.containerIdentifier
            await service.updateRelayContainerID(containerID)
        } else {
            await service.updateRelayContainerID(nil)
        }

        let textStream: @Sendable (LLMInput) async throws -> AsyncThrowingStream<String, Error> = { [weak self] input in
            guard let self else { return AsyncThrowingStream { continuation in continuation.finish() } }
            guard let remote = await self.remoteService else {
                return AsyncThrowingStream { continuation in continuation.finish() }
            }
            return await remote.stream(for: input)
        }

        client = AnyLLMClient(
            textStream: textStream,
            cancel: { [weak self] in
                Task { await self?.remoteService?.cancelActiveStream() }
            }
        )

        await service.updateToolSpecs(specs)

        loadedFormat = model.compatibilityFormat ?? .gguf
        supportsImageInput = false
        promptTemplate = nil
        loadError = nil
        loadedURL = nil
        loadedSettings = nil
        modelLoaded = true
        AccessibilityAnnouncer.announceLocalized("Model loaded.")
        currentKind = ModelKind.detect(id: modelIdentifier)
        modelManager?.loadedModel = nil
        let defaultTransport: RemoteSessionTransport
        let defaultStreaming: Bool
        switch backend.endpointType {
        case .noemaRelay:
            #if os(iOS) || os(visionOS)
            if let _ = initialLANSSID {
                defaultTransport = .lan(ssid: initialLANSSID ?? "")
            } else {
                defaultTransport = .cloudRelay
            }
            #else
            defaultTransport = .cloudRelay
            #endif
            defaultStreaming = false
        case .cloudRelay:
            defaultTransport = .cloudRelay
            defaultStreaming = false
        default:
            defaultTransport = .direct
            defaultStreaming = true
        }
        modelManager?.activeRemoteSession = ActiveRemoteSession(
            backendID: backend.id,
            backendName: backend.name,
            modelID: modelIdentifier,
            modelName: model.name,
            endpointType: backend.endpointType,
            transport: defaultTransport,
            streamingEnabled: defaultStreaming
        )

        let defaults = UserDefaults.standard
        if let fmt = loadedFormat { defaults.set(fmt.rawValue, forKey: "currentModelFormat") }
        defaults.set(true, forKey: "currentModelIsRemote")
        defaults.set(true, forKey: "currentModelSupportsFunctionCalling")

        let remoteWebSearchReady = SettingsStore.shared.webSearchArmed
            && WebToolGate.isAvailable(currentFormat: loadedFormat)
            && !specs.isEmpty
        systemPromptWebSearchOverride = remoteWebSearchReady

        // Record remote usage for review milestone tracking (prompting happens after a success moment).
        ReviewPrompter.shared.noteRemoteUsed()
    }

    func refreshActiveRemoteBackendIfNeeded(updatedBackendID: RemoteBackend.ID, activeModelID: String) async throws {
        guard let service = remoteService,
              let currentBackendID = activeRemoteBackendID,
              currentBackendID == updatedBackendID,
              let backend = modelManager?.remoteBackend(withID: updatedBackendID) else {
            return
        }
        await service.updateBackend(backend)
        await service.updateModelID(activeModelID)
        activeRemoteModelID = activeModelID
        if toolSpecsCache.isEmpty {
            let specs = await fetchToolSpecs()
            toolSpecsCache = specs
            await service.updateToolSpecs(specs)
        }
#if os(iOS) || os(visionOS)
        requestImmediateLANCheck(reason: "active-backend-refresh")
#endif
    }

#if os(iOS) || os(visionOS)
    func requestImmediateLANCheck(reason: String) {
        Task {
            guard let service = await self.remoteService else { return }
            await service.forceLANRefresh(reason: reason)
        }
    }

    func forceLANOverride(reason: String) {
        Task {
            guard let service = await self.remoteService else { return }
            await service.setLANManualOverride(true, reason: reason)
        }
    }

    private func refreshRelayBackend(backendID: RemoteBackend.ID) async -> RemoteBackend? {
        guard let manager = modelManager else { return nil }
        await manager.fetchRemoteModels(for: backendID)
        return manager.remoteBackend(withID: backendID)
    }
#endif

    private func updateActiveRemoteTransport(for backendID: RemoteBackend.ID,
                                             transport: RemoteSessionTransport,
                                             streaming: Bool) {
        guard let session = modelManager?.activeRemoteSession,
              session.backendID == backendID else {
            return
        }
        modelManager?.activeRemoteSession = ActiveRemoteSession(
            backendID: session.backendID,
            backendName: session.backendName,
            modelID: session.modelID,
            modelName: session.modelName,
            endpointType: session.endpointType,
            transport: transport,
            streamingEnabled: streaming
        )
    }

    func deactivateRemoteSession() {
        let backendID = activeRemoteBackendID
        let modelID = activeRemoteModelID
        var relayContext: (containerID: String, hostDeviceID: String, recordName: String)? = nil
        if let backendID, let modelID,
           let backend = modelManager?.remoteBackend(withID: backendID),
           backend.endpointType == .noemaRelay,
           backend.relayEjectsOnDisconnect {
            let containerID = backend.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            let hostID = backend.relayHostDeviceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !containerID.isEmpty, !hostID.isEmpty {
                let recordName = modelID.hasPrefix("model-") ? modelID : "model-\(modelID)"
                relayContext = (containerID, hostID, recordName)
            }
        }
        if let context = relayContext {
            Task {
                await sendRelayDeactivateCommand(containerID: context.containerID,
                                                 hostDeviceID: context.hostDeviceID,
                                                 recordName: context.recordName)
            }
        }
        unloadResources()
    }

    private func sendRelayDeactivateCommand(containerID: String, hostDeviceID: String, recordName: String) async {
        let payload: [String: Any] = [
            "modelRef": recordName,
            "ensure": "unloaded"
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        do {
            let command = try await RelayCatalogClient.shared.createCommand(
                containerIdentifier: containerID,
                hostDeviceID: hostDeviceID,
                verb: "POST",
                path: "/models/deactivate",
                body: body
            )
            let result = try await RelayCatalogClient.shared.waitForCommand(
                containerIdentifier: containerID,
                commandID: command.recordID,
                timeout: 60
            )
            if result.state != .succeeded {
                await logger.log("[RemoteBackendAPI] ⚠️ Relay eject returned state=\(result.state.rawValue)")
            }
        } catch {
            await logger.log("[RemoteBackendAPI] ❌ Failed to request relay eject: \(error.localizedDescription)")
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
        
        // Do not remove rolling thought boxes when stopping; finalize their state instead
        for viewModel in rollingThoughtViewModels.values {
            if viewModel.isLogicallyComplete {
                viewModel.finish()
            } else {
                viewModel.markInterrupted()
            }
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

    private func markRollingThoughtsInterrupted(forMessageAt index: Int) {
        guard streamMsgs.indices.contains(index) else { return }
        let messageID = streamMsgs[index].id.uuidString
        let prefix = "message-\(messageID)-think-"
        for (key, viewModel) in rollingThoughtViewModels where key.hasPrefix(prefix) {
            if !viewModel.isLogicallyComplete {
                viewModel.markInterrupted()
            }
        }
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
        try? await ensureClient(url: url, settings: loadedSettings, format: loadedFormat, forceReload: false)
        streamSessionIndex = nil
    }
    
    private func appendUser(_ text: String, purpose: RunPurpose) {
        precondition(purpose == .chat, "appendUser used for non-chat run")
        var m = msgs
        let datasetSnapshot: (id: String, name: String)? = {
            guard loadedFormat != .some(.slm),
                  let ds = modelManager?.activeDataset,
                  ds.isIndexed else { return nil }
            return (ds.datasetID, ds.name)
        }()
        m.append(.init(role: "🧑‍💻",
                       text: text,
                       timestamp: Date(),
                       datasetID: datasetSnapshot?.id,
                       datasetName: datasetSnapshot?.name))
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

        if isStreamingInAnotherSession {
            if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prompt = input
            }
            crossSessionSendBlocked = true
            Task { await logger.log("[ChatVM] Blocking send: another chat is still generating") }
            return
        }

        prompt = ""
        AccessibilityAnnouncer.announceLocalized("Prompt submitted.")

        let datasetSnapshot: (id: String, name: String)? = {
            guard loadedFormat != .some(.slm),
                  let ds = modelManager?.activeDataset,
                  ds.isIndexed else { return nil }
            return (ds.datasetID, ds.name)
        }()

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
        m.append(.init(role: "🧑‍💻",
                       text: input,
                       timestamp: Date(),
                       datasetID: datasetSnapshot?.id,
                       datasetName: datasetSnapshot?.name))
        self.streamMsgs = m
        // Snapshot attachments at send time so UI can clear the input tray immediately
        // Track which image file paths this specific run uses, so prior/next runs
        // cannot accidentally clear attachments they don't own.
        var usedImagePathsForThisRun: [String] = []
        let attachments = pendingImageURLs.map { $0.path }
        if !attachments.isEmpty {
            m = self.streamMsgs
            let idx = m.index(before: m.endIndex)
            m[idx].imagePaths = attachments
            self.streamMsgs = m
            // Mark these specific paths as the attachments for this run
            usedImagePathsForThisRun = attachments
            // Immediately remove used attachments from the input tray to avoid
            // showing them while generation is in progress. The sent images remain
            // visible on the user message via msg.imagePaths.
            for path in attachments {
                let url = URL(fileURLWithPath: path)
                if let i = pendingImageURLs.firstIndex(of: url) { pendingImageURLs.remove(at: i) }
                pendingThumbnails.removeValue(forKey: url)
            }
        }
        m = self.streamMsgs
        m.append(.init(role: "🤖", text: "", timestamp: Date(), streaming: true))
        self.streamMsgs = m
        let outIdx = self.streamMsgs.index(before: self.streamMsgs.endIndex)
        let history = self.streamMsgs
        let messageID = self.streamMsgs[outIdx].id

        systemPromptWebSearchOverride = nil
        var remoteToolsAllowedOverride: Bool? = nil
        if let remoteService = self.remoteService {
            var allowTools = SettingsStore.shared.webSearchArmed && WebToolGate.isAvailable(currentFormat: self.loadedFormat)
            if allowTools {
                let specs = await self.fetchToolSpecs()
                if specs.isEmpty {
                    allowTools = false
                } else {
                    await remoteService.updateToolSpecs(specs)
                }
            }
            remoteToolsAllowedOverride = allowTools
        }
        systemPromptWebSearchOverride = remoteToolsAllowedOverride

        // Use local backends only.

        var promptStr: String
        var stops: [String]
        var llmInput: LLMInput
        
        if loadedFormat == .slm {
            promptStr = input
            stops = loadedSettings?.stopSequences ?? []
            let userMessage = ChatMessage(role: "user", content: input)
            llmInput = LLMInput(.messages([userMessage]))
        } else {
            let (basePrompt, s, _) = self.buildPrompt(kind: currentKind, history: history)
            promptStr = basePrompt
            var mergedStops = s
            if mergedStops.isEmpty {
                if let overrideStops = (loadedSettings?.stopSequences ?? nil), !overrideStops.isEmpty {
                    mergedStops = overrideStops
                }
            }
            stops = mergedStops
            llmInput = LLMInput(.plain("") ) // will assign after final prompt computed
        }
        let isMLXFormat = (self.loadedFormat == .mlx)
        // Log prompt summary to the app log for diagnostics
        do {
            let previewLimit = 500
            let preview: String = {
                if isMLXFormat { return promptStr }
                if promptStr.count > previewLimit { return String(promptStr.prefix(previewLimit)) + "… [truncated]" }
                return promptStr
            }()
            let logMessage = "[ChatVM] Prompt built len=\(promptStr.count) stops=\(stops.count)\n\(preview)"
            Task {
                if isMLXFormat {
                    await logger.log(logMessage, truncateConsole: false)
                } else {
                    await logger.log(logMessage)
                }
            }
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
                            ctx = detailed.enumerated().map { offset, element in
                                let src = element.source?.trimmingCharacters(in: .whitespacesAndNewlines)
                                if let src, !src.isEmpty {
                                    return "[\(offset + 1)] (\(src)) \(element.text)"
                                }
                                return "[\(offset + 1)] \(element.text)"
                            }.joined(separator: "\n\n")
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
                        ctx = detailed.enumerated().map { offset, element in
                            let src = element.source?.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let src, !src.isEmpty {
                                return "[\(offset + 1)] (\(src)) \(element.text)"
                            }
                            return "[\(offset + 1)] \(element.text)"
                        }.joined(separator: "\n\n")
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
                    ctx = detailed.enumerated().map { offset, element in
                        let src = element.source?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let src, !src.isEmpty {
                            return "[\(offset + 1)] (\(src)) \(element.text)"
                        }
                        return "[\(offset + 1)] \(element.text)"
                    }.joined(separator: "\n\n")
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
                // Milestone: a RAG flow was used in chat (full or rag injection)
                ReviewPrompter.shared.noteRAGUsed()
                ReviewPrompter.shared.safeMaybePromptIfEligible(chatVM: self)
            }
            if client == nil, let url = loadedURL {
                try? await ensureClient(url: url, settings: loadedSettings, format: loadedFormat, forceReload: false)
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
        let promptPreview: String = {
            if isMLXFormat { return promptStr }
            if promptStr.count > promptPreviewLimit { return String(promptStr.prefix(promptPreviewLimit)) + "… [truncated]" }
            return promptStr
        }()
        Task {
            if isMLXFormat {
                await logger.log("[Prompt] \(promptPreview)", truncateConsole: false)
            } else {
                await logger.log("[Prompt] \(promptPreview)")
            }
        }
        if injectionStage != .none {
            let methodStr: String = {
                if didInjectDataset { return "dataset" }
                switch injectionMethod {
                case .some(.full): return "full"
                case .some(.rag):  return "rag"
                case .none:        return "unknown"
                }
            }()
            Task {
                let message = "[Prompt][RAG] Context injected: \(methodStr) · size=\(promptPreview.count) preview=\(promptPreview.prefix(200))…"
                if isMLXFormat {
                    await logger.log(message, truncateConsole: false)
                } else {
                    await logger.log(message)
                }
            }
        } else {
            Task { await logger.log("[Prompt][RAG] No context injected") }
        }
        Task { await logger.log("[Params] stops: \(stops)") }

        didLaunchStreamTask = true
        currentStreamTask = Task { [weak self, sessionIndex = sIdx, messageID] in
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
            AccessibilityAnnouncer.announceLocalized("Generating response…")
            let start = Date()
            await self.beginPerfTracking(messageID: messageID, start: start)
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

            var shouldRestartWithToolResult = false
            do {
                // Build stop sequences. Avoid adding "Step N:" stops for CoT/SLM models to not truncate reasoning-only streams.
                let isCotTemplate = (self.promptTemplate?.contains("<think>") == true)
                let defaultStopsBase = ["</s>", "<|im_end|>", "<|eot_id|>", "<end_of_turn>", "<eos>", "<｜User｜>", "<|User|>"]
                let defaultStops: [String] = {
                    if isCotTemplate || self.loadedFormat == .slm || (self.modelManager?.activeDataset != nil) { return defaultStopsBase }
                    return defaultStopsBase + ["Step 1:", "Step 2:"]
                }()
                let stopSeqs = stops.isEmpty ? defaultStops : stops
                // Use the attachments snapshot from send time; do not consult
                // pendingImageURLs here because we clear them when the message is sent.
                let imagePaths = usedImagePathsForThisRun
                let useImages = self.supportsImageInput && !imagePaths.isEmpty && (self.loadedFormat == .mlx || self.loadedFormat == .gguf || self.loadedFormat == .slm)
                // Preserve the snapshot if images are allowed; otherwise mark empty.
                usedImagePathsForThisRun = useImages ? imagePaths : []
                if !imagePaths.isEmpty {
                    if useImages {
                        let names = imagePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
                        Task { await logger.log("[Images][Use] yes format=\(String(describing: self.loadedFormat)) count=\(imagePaths.count) names=\(names.joined(separator: ", "))") }
                    } else {
                        var reasons: [String] = []
                        if !self.supportsImageInput { reasons.append("supportsImageInput=false") }
                        if !(self.loadedFormat == .mlx || self.loadedFormat == .gguf || self.loadedFormat == .slm) {
                            reasons.append("format=\(String(describing: self.loadedFormat)) unsupported")
                        }
                        Task { await logger.log("[Images][Use] no reasons=\(reasons.joined(separator: ",")) count=\(imagePaths.count)") }
                    }
                }
                // If images are present and supported, inject image placeholders only for llama.cpp or MLX templates
                // For Leap SLM, do NOT inject placeholders; send raw text plus image binaries via multimodal
                let finalPrompt = promptStr
                if self.loadedFormat != .slm {
                    llmInput = useImages ? LLMInput.multimodal(text: finalPrompt, imagePaths: imagePaths)
                                          : LLMInput(.plain(finalPrompt))
                }
                if let remoteService = self.remoteService {
                    let allowTools = remoteToolsAllowedOverride ?? false
                    let temperature = self.loadedSettings?.temperature ?? 0.7
                    await remoteService.updateOptions(
                        stops: stopSeqs,
                        temperature: temperature,
                        includeTools: allowTools
                    )
                }
                // For remote sessions, show a brief loading indicator when starting
                // the first stream, instead of on model selection.
                if self.remoteService != nil && self.remoteLoadingPending == false {
                    self.remoteLoadingPending = true
                }
                if self.remoteLoadingPending {
                    await MainActor.run {
                        let format = self.loadedFormat ?? .gguf
                        self.loadingProgressTracker.startLoading(for: format)
                    }
                }
                // Emit a start log for this generation
                Task { await logger.log("[ChatVM] ▶︎ Starting generation (format=\(String(describing: self.loadedFormat)), kind=\(self.currentKind), images=\(useImages ? imagePaths.count : 0))") }
                // Flip to Predicting when first token arrives
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
                        if inThink && self.remoteService == nil { continue }
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
                            await self.handleRollingThoughts(raw: raw, messageIndex: outIdx)
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
                                // Decode SearXNG-style [WebHit] payload
                                struct SimpleWebHit: Decodable {
                                    let title: String
                                    let url: String
                                    let snippet: String
                                    let engine: String?
                                    let score: Double?
                                }
                                if let hits = try? JSONDecoder().decode([SimpleWebHit].self, from: data) {
                                    await MainActor.run {
                                        if self.streamMsgs.indices.contains(outIdx) {
                                            self.streamMsgs[outIdx].usedWebSearch = true
                                            self.streamMsgs[outIdx].webError = nil
                                            self.streamMsgs[outIdx].webHits = hits.enumerated().map { (i, h) in
                                                let engine = h.engine?.trimmingCharacters(in: .whitespacesAndNewlines)
                                                let resolvedEngine = engine?.isEmpty == false ? engine! : "searxng"
                                                return .init(
                                                    id: String(i+1),
                                                    title: h.title,
                                                    snippet: h.snippet,
                                                    url: h.url,
                                                    engine: resolvedEngine,
                                                    score: h.score ?? 0
                                                )
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
                        if self.remoteLoadingPending {
                            await MainActor.run {
                                self.loadingProgressTracker.completeLoading()
                            }
                            self.remoteLoadingPending = false
                        }
                        await MainActor.run { if self.injectionStage != .none { self.injectionStage = .predicting } }
                        if self.currentKind == .gemma && !self.gemmaAutoTemplated {
                            let t = trimmedTok
                            if !t.hasPrefix("<|") { self.gemmaAutoTemplated = true }
                        }
                        // Keep the decision banner visible until streaming completes to improve UX feedback
                        Task { await logger.log("[ChatVM] First token received") }
                    }
                    count += 1
                    await self.recordToken(messageID: messageID)
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
                            await self.handleRollingThoughts(raw: raw, messageIndex: outIdx)
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
                let wasCancellation = (error as? CancellationError) != nil
                await MainActor.run {
                    guard myID == self.activeRunID,
                          self.streamMsgs.indices.contains(outIdx) else { return }
                    self.streamMsgs[outIdx].streaming = false
                    // Consider an in‑app review prompt after a successful turn.
                    ReviewPrompter.shared.safeMaybePromptIfEligible(chatVM: self)
                    if !wasCancellation {
                        let lower = error.localizedDescription.lowercased()
                        if !lower.contains("decode") {
                            self.streamMsgs[outIdx].text = "⚠️ " + error.localizedDescription
                        }
                    }
                }
                if !wasCancellation {
                    self.markRollingThoughtsInterrupted(forMessageAt: outIdx)
                }
                if self.remoteLoadingPending {
                    await MainActor.run {
                        self.loadingProgressTracker.completeLoading()
                    }
                    self.remoteLoadingPending = false
                }
                await self.cancelPerfTracking(messageID: messageID)
                return
            }
            if pendingToolJSON == nil, let remoteService = await self.remoteService {
                let bufferedTokens = await remoteService.drainBufferedToolTokens()
                if !bufferedTokens.isEmpty {
                    for token in bufferedTokens {
                        if Task.isCancelled { break }
                        if shouldRestartWithToolResult { break }
                        let trimmedTok = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedTok.isEmpty else { continue }
                        if trimmedTok.hasPrefix("TOOL_RESULT:") {
                            let json = trimmedTok.replacingOccurrences(of: "TOOL_RESULT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { await logger.log("[Tool][Stream][Buffered] TOOL_RESULT raw: \(json)") }
                            if let data = json.data(using: .utf8) {
                                struct BufferedSimpleWebHit: Decodable {
                                    let title: String
                                    let url: String
                                    let snippet: String
                                    let engine: String?
                                    let score: Double?
                                }
                                if let hits = try? JSONDecoder().decode([BufferedSimpleWebHit].self, from: data) {
                                    await MainActor.run {
                                        if self.streamMsgs.indices.contains(outIdx) {
                                            self.streamMsgs[outIdx].usedWebSearch = true
                                            self.streamMsgs[outIdx].webError = nil
                                            self.streamMsgs[outIdx].webHits = hits.enumerated().map { (i, h) in
                                                let engine = h.engine?.trimmingCharacters(in: .whitespacesAndNewlines)
                                                let resolvedEngine = engine?.isEmpty == false ? engine! : "searxng"
                                                return .init(
                                                    id: String(i+1),
                                                    title: h.title,
                                                    snippet: h.snippet,
                                                    url: h.url,
                                                    engine: resolvedEngine,
                                                    score: h.score ?? 0
                                                )
                                            }
                                        }
                                    }
                                } else if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
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
                            pendingAssistantText = raw
                            pendingToolJSON = json
                            shouldRestartWithToolResult = true
                            c.cancelActive()
                            break
                        } else if trimmedTok.hasPrefix("TOOL_CALL:") {
                            Task { await logger.log("[Tool][Stream][Buffered] TOOL_CALL token: \(trimmedTok)") }
                            await MainActor.run {
                                if self.streamMsgs.indices.contains(outIdx) {
                                    self.streamMsgs[outIdx].usedWebSearch = true
                                }
                            }
                            if let (handled, trailing) = await interceptToolCallIfPresent(trimmedTok, messageIndex: outIdx, chatVM: self) {
                                pendingAssistantText = raw
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
                                await self.handleRollingThoughts(raw: raw, messageIndex: outIdx)
                                let json = handled.replacingOccurrences(of: "TOOL_RESULT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                                pendingToolJSON = json
                                didProcessEmbeddedToolCall = true
                                shouldRestartWithToolResult = true
                                c.cancelActive()
                                break
                            }
                        }
                    }
                }
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
                    await self.handleRollingThoughts(raw: raw, messageIndex: outIdx)
                    let json = handled.replacingOccurrences(of: "TOOL_RESULT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    pendingToolJSON = json
                    didProcessEmbeddedToolCall = true
                }
            }

            if self.remoteLoadingPending {
                await MainActor.run {
                    self.loadingProgressTracker.completeLoading()
                }
                self.remoteLoadingPending = false
            }

            // Do not hide or alter chain-of-thought: preserve full model output including <think> sections.
            // Avoid transforming enumerations (e.g., "Step 1:") to keep original thinking intact.
            let cleaned = self.cleanOutput(raw, kind: self.currentKind)
            let injectionOverhead = (self.injectionMethod == .full && self.currentInjectedTokenOverhead > 0) ? self.currentInjectedTokenOverhead : 0
            let perfResult: Msg.Perf? = shouldRestartWithToolResult ? nil : await self.finalizePerf(messageID: messageID, injectionOverhead: injectionOverhead)
            await self.finalizeAssistantStream(
                runID: myID,
                messageIndex: outIdx,
                cleanedText: cleaned,
                pendingToolJSON: pendingToolJSON,
                perfResult: perfResult,
                tokenCount: count,
                generationStart: start,
                firstTokenTimestamp: firstTok,
                isMLXFormat: isMLXFormat
            )
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
                self.currentContinuationTask = Task { [weak self, pendingAssistantText, sessionIndex = sIdx, messageID] in
                    guard let self else { return }
                    defer {
                        Task { @MainActor in
                            if self.streamSessionIndex == sessionIndex {
                                self.streamSessionIndex = nil
                            }
                        }
                    }
                    guard let client = self.client else {
                        await self.cancelPerfTracking(messageID: messageID)
                        return
                    }
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
                            // Begin waiting for post-tool continuation tokens
                            self.streamMsgs[outIdx].postToolWaiting = true
                            AccessibilityAnnouncer.announceLocalized("Generating response…")
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

                        let baseAssistantText = localHistory.indices.contains(outIdx) ? localHistory[outIdx].text : ""
                        var continuation = ""
                        var nextToolJSON: String? = nil
                        let maxContTokens = Int(self.contextLimit * 0.4)
                        var contTokCount = 0
                        do {
                        // Stream continuation using the rebuilt prompt (SLM path reuses the ongoing Leap conversation).
                            guard let input = postToolInput else { break }
                            for try await t in try await client.textStream(from: input) {
                                if Task.isCancelled { break }
                                await self.recordToken(messageID: messageID)
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
                                        let continuationText: String = await MainActor.run {
                                            if self.streamMsgs.indices.contains(outIdx) {
                                                return self.streamMsgs[outIdx].text
                                            } else {
                                                return continuation
                                            }
                                        }
                                        await self.handleRollingThoughts(raw: continuationText, messageIndex: outIdx)
                                        // Another tool call was executed mid-continuation; show the
                                        // post-tool waiting spinner again until next tokens stream.
                                        await MainActor.run {
                                            if self.streamMsgs.indices.contains(outIdx) {
                                                self.streamMsgs[outIdx].postToolWaiting = true
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
                                    let continuationText: String = await MainActor.run {
                                        if self.streamMsgs.indices.contains(outIdx) {
                                            return self.streamMsgs[outIdx].text
                                        } else {
                                            return continuation
                                        }
                                    }
                                    await self.handleRollingThoughts(raw: continuationText, messageIndex: outIdx)
                                    // Stop the current continuation stream before starting the next tool turn
                                    client.cancelActive()
                                    break
                                }

                                let appendChunk = nonOverlappingDelta(newChunk: t, existing: continuation)
                                continuation += appendChunk
                                contTokCount += 1

                                // First token of post-tool continuation: hide waiting spinner
                                if contTokCount == 1 {
                                    await MainActor.run {
                                        if self.streamMsgs.indices.contains(outIdx) {
                                            self.streamMsgs[outIdx].postToolWaiting = false
                                        }
                                    }
                                }

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

                        if nextToolJSON == nil {
                            let combinedText = baseAssistantText + continuation
                            if let (handled, cleaned) = await interceptEmbeddedToolCallIfPresent(
                                in: combinedText,
                                messageIndex: outIdx,
                                chatVM: self
                            ) {
                                let inlineTokens = handled + "\n"
                                let nextJSON = handled
                                    .replacingOccurrences(of: "TOOL_RESULT:", with: "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                nextToolJSON = nextJSON
                                pendingAssistantText = cleaned

                                let updatedText = cleaned + inlineTokens
                                let appendedPortion: String = {
                                    if updatedText.count >= baseAssistantText.count {
                                        let startIndex = updatedText.index(updatedText.startIndex, offsetBy: baseAssistantText.count)
                                        return String(updatedText[startIndex...])
                                    }
                                    return updatedText
                                }()
                                continuation = appendedPortion

                                await MainActor.run {
                                    if self.streamMsgs.indices.contains(outIdx) {
                                        self.streamMsgs[outIdx].text = updatedText
                                        if let toolName = self.streamMsgs[outIdx].toolCalls?.last?.toolName,
                                           toolName == "noema.web.retrieve" {
                                            self.streamMsgs[outIdx].usedWebSearch = true
                                        }
                                    }
                                }
                                await self.handleRollingThoughts(raw: updatedText, messageIndex: outIdx)
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

                    let continuationOverhead = (self.injectionMethod == .full && self.currentInjectedTokenOverhead > 0) ? self.currentInjectedTokenOverhead : 0
                    let finalPerf = await self.finalizePerf(messageID: messageID, injectionOverhead: continuationOverhead)
                    await MainActor.run {
                        if self.streamMsgs.indices.contains(outIdx) {
                            self.streamMsgs[outIdx].streaming = false
                            self.streamMsgs[outIdx].postToolWaiting = false
                            if let perf = finalPerf {
                                self.streamMsgs[outIdx].perf = perf
                            }
                            // Consider an in‑app review prompt after a successful turn.
                            ReviewPrompter.shared.safeMaybePromptIfEligible(chatVM: self)
                            AccessibilityAnnouncer.announceLocalized("Response generated.")
                        }
                    }
                    self.markRollingThoughtsInterrupted(forMessageAt: outIdx)
                    await MainActor.run { self.currentContinuationTask = nil }
                }
            }
        }
        // Do not immediately clear the banner here; allow the delayed clear above
        currentInjectedTokenOverhead = 0
        // Only clear images actually used by THIS run to avoid races.
        var removedCount = 0
        if !usedImagePathsForThisRun.isEmpty {
            let usedSet = Set(usedImagePathsForThisRun)
            // Map paths to URLs and remove if still pending
            for path in usedSet {
                let url = URL(fileURLWithPath: path)
                if let idx = pendingImageURLs.firstIndex(of: url) {
                    pendingImageURLs.remove(at: idx)
                    pendingThumbnails.removeValue(forKey: url)
                    removedCount += 1
                }
            }
        }
        if removedCount > 0 {
            Task { await logger.log("[Images][Clear] cleared=\(removedCount)") }
        }
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
                        // If the model emitted an opening tag without closing it yet
                        // (common when it streams both JSON and XML variants before we
                        // cancel for tool execution), avoid discarding the remaining
                        // response. Instead, best-effort trim the JSON payload directly
                        // following the tag so subsequent parsing can continue.
                        if let brace = rest.firstIndex(of: "{"),
                           let close = findMatchingBrace(in: rest, startingFrom: brace) {
                            let after = rest.index(after: close)
                            rest = rest[after...]
                        } else if let bracket = rest.firstIndex(of: "["),
                                  let close = findMatchingBracket(in: rest, startingFrom: bracket) {
                            let after = rest.index(after: close)
                            rest = rest[after...]
                        }
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
                toolLoop: while let toolRange = rest.range(of: "<tool_response>") ?? rest.range(of: "TOOL_RESULT:") {
                    // Emit text before the tool block
                    if toolRange.lowerBound > rest.startIndex {
                        finalPieces.append(.text(String(rest[..<toolRange.lowerBound])))
                    }

                    let markerSlice = rest[toolRange]
                    var remainder = rest[toolRange.upperBound...]
                    var consumedPayload = false

                    if markerSlice.hasPrefix("<tool_response>") {
                        if let end = remainder.range(of: "</tool_response>") {
                            remainder = remainder[end.upperBound...]
                            consumedPayload = true
                        }
                    } else {
                        // Skip TOOL_RESULT JSON payloads. These can be objects or arrays.
                        var idx = remainder.startIndex
                        while idx < remainder.endIndex && remainder[idx].isWhitespace {
                            idx = remainder.index(after: idx)
                        }
                        if idx < remainder.endIndex {
                            if remainder[idx] == "[" {
                                if let close = findMatchingBracket(in: remainder, startingFrom: idx) {
                                    remainder = remainder[remainder.index(after: close)...]
                                    consumedPayload = true
                                }
                            } else if remainder[idx] == "{" {
                                if let close = findMatchingBrace(in: remainder, startingFrom: idx) {
                                    remainder = remainder[remainder.index(after: close)...]
                                    consumedPayload = true
                                }
                            } else {
                                // Unknown payload: drop through to the next newline to avoid leaking JSON.
                                if let newline = remainder[idx...].firstIndex(of: "\n") {
                                    remainder = remainder[newline...]
                                } else {
                                    remainder = remainder[remainder.endIndex...]
                                }
                                consumedPayload = true
                            }
                        } else {
                            remainder = remainder[idx...]
                            consumedPayload = true
                        }
                    }

                    // Tool response doesn't increment the index since it's for the same tool call
                    finalPieces.append(.tool(toolCallIndex))
                    rest = remainder
                    if !consumedPayload { break toolLoop }
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
        Use the following information to answer the question. Cite sources using bracketed numbers like [1], [2], etc. In <think>...</think>, reason about how each cited passage answers the question before writing the final response.
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
extension ChatVM {
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
    func buildPrompt(kind: ModelKind, history: [ChatVM.Msg]) -> (String, [String], Int?) {
        // Use the unified formatter to prepare messages vs plain prompt
        let cfMessages: [ChatFormatter.Message] = history.map { m in
            let roleLower = m.role.lowercased()
            let normalizedRole: String
            if roleLower == "🧑‍💻".lowercased() { normalizedRole = "user" }
            else if roleLower == "🤖".lowercased() { normalizedRole = "assistant" }
            else { normalizedRole = roleLower }
            return ChatFormatter.Message(role: normalizedRole, content: m.text)
        }
        let systemPrompt = systemPromptText
        Task {
            await logger.log("[ChatVM] SYSTEM PROMPT\n\(systemPrompt)")
        }
        let rendered = prepareForGeneration(messages: history, system: systemPrompt)
        switch rendered {
        case .messages(let arr):
            // Convert back to ChatVM.Msg for our renderer
            let msgs: [ChatVM.Msg] = arr.map { ChatVM.Msg(role: $0.role, text: $0.content) }
            return PromptBuilder.build(template: promptTemplate, family: kind, messages: msgs)
        case .plain(let s):
            // Let caller pick default stops; provide generous token budget
            return (s, [], nil)
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
    fileprivate static func parseCodeBlocks(_ text: String) -> [Piece] {
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
    @MainActor
    func savePendingImage(_ image: UIImage) async {
        // Persist to temporary directory so we can pass file paths into model clients
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("noema_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        let url = dir.appendingPathComponent(UUID().uuidString + ".jpg")
        try? data.write(to: url)

        // Prepare and cache a small thumbnail once so typing doesn't force re-decodes.
        // Target ~160pt to look crisp at 80pt cells on 2x displays.
        let target = CGSize(width: 160, height: 160)
        #if canImport(UIKit)
        if let thumb = await image.byPreparingThumbnail(ofSize: target) ?? image.resizedDown(to: target) {
            pendingThumbnails[url] = thumb
        }
        #else
        if let thumb = image.resizedDown(to: target) {
            pendingThumbnails[url] = thumb
        }
        #endif

        pendingImageURLs.append(url)
        let w = Int(image.size.width), h = Int(image.size.height)
        Task { await logger.log("[Images][Attach] saved=\(url.lastPathComponent) size=\(w)x\(h) path=\(url.path) pending=\(pendingImageURLs.count)") }
    }

    @MainActor
    func removePendingImage(at index: Int) {
        guard pendingImageURLs.indices.contains(index) else { return }
        let url = pendingImageURLs.remove(at: index)
        pendingThumbnails.removeValue(forKey: url)
        try? FileManager.default.removeItem(at: url)
        Task { await logger.log("[Images][Remove] removed=\(url.lastPathComponent) pending=\(pendingImageURLs.count)") }
    }

    // Accessor used by views to fetch cached thumbnails
    func pendingThumbnail(for url: URL) -> UIImage? {
        pendingThumbnails[url]
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

        // Compute removals and additions first
        var keysToRemove: [String] = []
        for key in rollingThoughtViewModels.keys where !allowedKeys.contains(key) {
            keysToRemove.append(key)
        }

        var modelsToAdd: [String: RollingThoughtViewModel] = [:]
        for key in allowedKeys where rollingThoughtViewModels[key] == nil {
            let vm = RollingThoughtViewModel()
            if let tuple = keyToContent[key] {
                vm.fullText = tuple.content
                vm.updateRollingLines()
                vm.phase = tuple.isComplete ? .complete : .expanded
            }
            modelsToAdd[key] = vm
        }

        // Apply all mutations in one deferred main-queue pass to avoid nested updates
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for key in keysToRemove {
                self.rollingThoughtViewModels[key]?.cancel()
                self.rollingThoughtViewModels.removeValue(forKey: key)
            }
            for (key, vm) in modelsToAdd {
                self.rollingThoughtViewModels[key] = vm
            }
        }
    }
    
    /// Returns only the assistant-visible answer text, stripping think/tool blocks
    /// and preferring content that appears after the final control segment.
    func finalAnswerText(for message: Msg) -> String? {
        let pieces = parse(message.text, toolCalls: message.toolCalls)
        guard !pieces.isEmpty else { return nil }
        
        let lastControlIndex = pieces.lastIndex { piece in
            switch piece {
            case .think, .tool:
                return true
            default:
                return false
            }
        }
        
        var segments: [String] = []
        for (index, piece) in pieces.enumerated() {
            guard case .text(let text) = piece else { continue }
            if let last = lastControlIndex, index <= last { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(trimmed)
            }
        }
        
        var combined = segments.joined(separator: "\n")
        if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fallbackSegments = pieces.compactMap { piece -> String? in
                guard case .text(let text) = piece else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            combined = fallbackSegments.joined(separator: "\n")
        }
        
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension ChatVM: ModelBenchmarkingViewModel {
    func unloadAfterBenchmark() async {
        await unload()
    }
}

// MARK: –– Chat UI ----------------------------------------------------------

/// Renders a single message. Any text between `<think>` tags is wrapped in a
/// collapsible box with rounded corners.
struct MessageView: View {
    let msg: ChatVM.Msg
    @EnvironmentObject var vm: ChatVM
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedThinkIndices: Set<Int> = []
    @State private var showCopyPopup = false
    @State private var copiedMessage = false
    @State private var expandedImagePath: String? = nil
#if os(macOS)
    @State private var hoverCopyVisible = false
    @State private var suppressHoverCopy = false
#endif
#if os(visionOS)
    @EnvironmentObject private var pinnedStore: VisionPinnedNoteStore
    @Environment(\.openWindow) private var openWindow
    @State private var hoverActive = false
    @State private var showInteractionOptions = false
    @GestureState private var isPressingMessage = false
#endif
    
    private var datasetDisplayName: String? {
        if let stored = msg.datasetName, !stored.isEmpty { return stored }
        if let id = msg.datasetID,
           let ds = vm.datasetManager?.datasets.first(where: { $0.datasetID == id }) {
            return ds.name
        }
        return nil
    }
    
    private func parse(_ text: String, toolCalls: [ChatVM.Msg.ToolCall]? = nil) -> [ChatVM.Piece] {
        // First parse code blocks
        let codeBlocks = ChatVM.parseCodeBlocks(text)
        
        // Then parse think tags within each text piece
        var finalPieces: [ChatVM.Piece] = []
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
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 { toolCallIndex += 1 }
                    insertedToolFromCodeBlock = true
                }
                // 2) TOOL_CALL:/TOOL_RESULT markers inside code fences
                tmp = codeSub
                while let callRange = tmp.range(of: "TOOL_CALL:") {
                    tmp = tmp[callRange.upperBound...]
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
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
                            finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
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
                    finalPieces.append(ChatVM.Piece.code(code, language: lang))
                }
            case .text(let t):
                // Parse think tags in text
                var rest = t[...]
                // Detect multiple inline tool_call blocks
                func appendTextWithThinks(_ segment: Substring) {
                    var tmp = segment
                    while let s = tmp.range(of: "<think>") {
                        if s.lowerBound > tmp.startIndex {
                            // Strip any stray closing tags in plain text
                            let beforeText = String(tmp[..<s.lowerBound]).replacingOccurrences(of: "</think>", with: "")
                            finalPieces.append(ChatVM.Piece.text(beforeText))
                        }
                        tmp = tmp[s.upperBound...]
                        if let e = tmp.range(of: "</think>") {
                            let inner = String(tmp[..<e.lowerBound])
                            // Sanitize nested or stray think markers inside the box content
                            let sanitizedInner = inner
                                .replacingOccurrences(of: "<think>", with: "")
                                .replacingOccurrences(of: "</think>", with: "")
                            finalPieces.append(ChatVM.Piece.think(sanitizedInner, done: true))
                            tmp = tmp[e.upperBound...]
                        } else {
                            let partial = String(tmp)
                                .replacingOccurrences(of: "<think>", with: "")
                                .replacingOccurrences(of: "</think>", with: "")
                            finalPieces.append(ChatVM.Piece.think(partial, done: false))
                            tmp = tmp[tmp.endIndex...]
                        }
                    }
                    if !tmp.isEmpty {
                        let trailingText = String(tmp).replacingOccurrences(of: "</think>", with: "")
                        finalPieces.append(ChatVM.Piece.text(trailingText))
                    }
                }
                while let callTag = rest.range(of: "<tool_call>") {
                    if callTag.lowerBound > rest.startIndex { appendTextWithThinks(rest[..<callTag.lowerBound]) }
                    rest = rest[callTag.upperBound...]
                    if let end = rest.range(of: "</tool_call>") {
                        rest = rest[end.upperBound...]
                    } else {
                        rest = rest[rest.endIndex...]
                    }
                    // Use the current tool call index and increment for next one
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                        toolCallIndex += 1
                    }
                }
                // Detect multiple TOOL_CALL markers
                while let callRange = rest.range(of: "TOOL_CALL:") {
                    if callRange.lowerBound > rest.startIndex { appendTextWithThinks(rest[..<callRange.lowerBound]) }
                    var after = rest[callRange.upperBound...]
                    if let nextResp = (after.range(of: "<tool_response>") ?? after.range(of: "TOOL_RESULT:")) {
                        rest = after[nextResp.lowerBound...]
                    } else if let nl = after.firstIndex(of: "\n") {
                        rest = after[nl...]
                    } else {
                        rest = rest[rest.endIndex...]
                    }
                    // Use the current tool call index and increment for next one
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                        toolCallIndex += 1
                    }
                }
                
                // Detect bare JSON tool call objects and hide them inline
                // Looks for a JSON object containing either "tool_name" or legacy "name" along with "arguments"
                var searchStart = rest.startIndex
                scanJSON: while let braceStart = rest[searchStart...].firstIndex(of: "{") {
                    let maybeEnd = findMatchingBrace(in: rest, startingFrom: braceStart)
                    if let braceEnd = maybeEnd {
                        let candidate = rest[braceStart...braceEnd]
                        if (candidate.contains("\"tool_name\"") || candidate.contains("\"name\"")) && candidate.contains("\"arguments\"") {
                            // Emit text before the JSON block
                            if braceStart > rest.startIndex { appendTextWithThinks(rest[..<braceStart]) }
                            // Skip over the JSON block and insert a tool box placeholder
                            let afterEnd = rest.index(after: braceEnd)
                            rest = rest[afterEnd...]
                            finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                            if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                                toolCallIndex += 1
                            }
                            // Restart search at beginning of updated remainder
                            searchStart = rest.startIndex
                            continue scanJSON
                        }
                    } else {
                        // Incomplete JSON; if it looks like a tool call, show placeholder and hide the partial content
                        let hasNameKey = rest.range(of: "\"name\"")
                        let hasToolNameKey = rest.range(of: "\"tool_name\"")
                        let hasArgsKey = rest.range(of: "\"arguments\"")
                        if (hasNameKey != nil || hasToolNameKey != nil), let argsRange = hasArgsKey {
                            if (hasNameKey?.lowerBound ?? braceStart) >= braceStart || argsRange.lowerBound >= braceStart {
                                if braceStart > rest.startIndex { appendTextWithThinks(rest[..<braceStart]) }
                                // Drop everything after the braceStart for now (will be replaced as stream continues)
                                rest = rest[rest.endIndex...]
                                finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                                if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                                    toolCallIndex += 1
                                }
                                break scanJSON
                            }
                        }
                        // Continue searching after this opening brace
                        searchStart = rest.index(after: braceStart)
                        continue scanJSON
                    }
                    // Continue searching after this opening brace if not matched
                    searchStart = rest.index(after: braceStart)
                }
                // Hide multiple tool_response blocks
                toolLoop: while let toolRange = rest.range(of: "<tool_response>") ?? rest.range(of: "TOOL_RESULT:") {
                    if toolRange.lowerBound > rest.startIndex { appendTextWithThinks(rest[..<toolRange.lowerBound]) }

                    let markerSlice = rest[toolRange]
                    var remainder = rest[toolRange.upperBound...]
                    var consumedPayload = false

                    if markerSlice.hasPrefix("<tool_response>") {
                        if let end = remainder.range(of: "</tool_response>") {
                            remainder = remainder[end.upperBound...]
                            consumedPayload = true
                        }
                    } else {
                        // TOOL_RESULT payload can be a JSON object or array; skip entire structure
                        var idx = remainder.startIndex
                        while idx < remainder.endIndex && remainder[idx].isWhitespace {
                            idx = remainder.index(after: idx)
                        }
                        if idx < remainder.endIndex {
                            if remainder[idx] == "[" {
                                if let close = findMatchingBracket(in: remainder, startingFrom: idx) {
                                    remainder = remainder[remainder.index(after: close)...]
                                    consumedPayload = true
                                }
                            } else if remainder[idx] == "{" {
                                if let close = findMatchingBrace(in: remainder, startingFrom: idx) {
                                    remainder = remainder[remainder.index(after: close)...]
                                    consumedPayload = true
                                }
                            } else {
                                if let newline = remainder[idx...].firstIndex(of: "\n") {
                                    remainder = remainder[newline...]
                                } else {
                                    remainder = remainder[remainder.endIndex...]
                                }
                                consumedPayload = true
                            }
                        } else {
                            remainder = remainder[idx...]
                            consumedPayload = true
                        }
                    }
                    // Tool response doesn't increment the index since it's for the same tool call
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                    rest = remainder
                    if !consumedPayload { break toolLoop }
                }
                // Preserve all think blocks (and sanitize inner content)
                while let s = rest.range(of: "<think>") {
                    if s.lowerBound > rest.startIndex {
                        let before = String(rest[..<s.lowerBound]).replacingOccurrences(of: "</think>", with: "")
                        finalPieces.append(ChatVM.Piece.text(before))
                    }
                    
                    rest = rest[s.upperBound...]
                    if let e = rest.range(of: "</think>") {
                        let inner = String(rest[..<e.lowerBound])
                            .replacingOccurrences(of: "<think>", with: "")
                            .replacingOccurrences(of: "</think>", with: "")
                        finalPieces.append(ChatVM.Piece.think(inner, done: true))
                        rest = rest[e.upperBound...]
                    } else {
                        let partial = String(rest)
                            .replacingOccurrences(of: "<think>", with: "")
                            .replacingOccurrences(of: "</think>", with: "")
                        finalPieces.append(ChatVM.Piece.think(partial, done: false))
                        rest = rest[rest.endIndex...]
                    }
                }
                if !rest.isEmpty {
                    let tail = String(rest).replacingOccurrences(of: "</think>", with: "")
                    finalPieces.append(ChatVM.Piece.text(tail))
                }
            case .think:
                // This shouldn't happen from parseCodeBlocks
                finalPieces.append(piece)
            case .tool(_):
                // Render-time handled via ToolCallView; skip here
                break
            }
        }
        
        return finalPieces
    }
    
    
    // MARK: - Text or List rendering
    // Units used to render text blocks while allowing lists to be combined
    // into a single selectable region.
    private enum RenderUnit { case bulletBlock(String); case entryIndex(Int) }
    @ViewBuilder
    private func renderTextOrList(_ t: String) -> some View {
        // Enhanced rendering:
        // - Headings: lines starting with "# ", "## ", "### ", etc. get larger fonts
        // - Bullets: single-character markers ('-', '*', '+', '•') render with a leading dot
        // - Math: each line still routes through MathRichText for LaTeX support
        let text = normalizeListFormatting(t)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else {
            let entries = parseTextEntries(from: text)
            // Precompute render units so the ViewBuilder only loops values.
            let units: [RenderUnit] = {
                var out: [RenderUnit] = []
                var i = 0
                while i < entries.count {
                    switch entries[i] {
                    case .blank, .heading, .mathBlock, .table, .text:
                        out.append(.entryIndex(i))
                        i += 1
                    case .bullet:
                        var lines: [String] = []
                        while i < entries.count {
                            if case .bullet(let marker, let content) = entries[i] {
                                lines.append("\(marker) \(content)")
                                i += 1
                            } else { break }
                        }
                        out.append(.bulletBlock(lines.joined(separator: "\n\n")))
                    }
                }
                return out
            }()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(units.enumerated()), id: \.offset) { _, unit in
                    switch unit {
                    case .bulletBlock(let block):
                        MathRichText(source: block, bodyFont: chatBodyFont)
                            .font(chatBodyFont)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .entryIndex(let idx):
                        switch entries[idx] {
                        case .blank:
                            Text("")
                        case .heading(let level, let content):
                            MathRichText(source: content, bodyFont: headingFont(for: level))
                                .font(headingFont(for: level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .mathBlock(let source):
                            MathRichText(source: source, bodyFont: chatBodyFont)
                                .font(chatBodyFont)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .table(let headers, let alignments, let rows):
                            tableView(headers: headers, alignments: alignments, rows: rows)
                        case .text(let line):
                            MathRichText(source: line, bodyFont: chatBodyFont)
                                .font(chatBodyFont)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .bullet:
                            // Should not appear as individual entries because bullets are grouped.
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    private enum TextLineEntry {
        case blank
        case heading(level: Int, content: String)
        case bullet(marker: String, content: String)
        case mathBlock(String)
        case table(headers: [String], alignments: [TableColumnAlignment], rows: [[String]])
        case text(String)
    }

    private enum TextBlockDelimiter {
        case doubleDollar
        case bracket
    }

    private enum TableColumnAlignment {
        case leading
        case center
        case trailing

        var gridAlignment: Alignment {
            switch self {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }

        var frameAlignment: Alignment {
            switch self {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }

        var textAlignment: TextAlignment {
            switch self {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }
    }

    private func parseTextEntries(from text: String) -> [TextLineEntry] {
        func startDelimiter(for trimmed: String) -> TextBlockDelimiter? {
            switch trimmed {
            case "$$": return .doubleDollar
            case "\\[": return .bracket
            default: return nil
            }
        }

        func closes(_ trimmed: String, matching delimiter: TextBlockDelimiter) -> Bool {
            switch delimiter {
            case .doubleDollar: return trimmed == "$$"
            case .bracket: return trimmed == "\\]"
            }
        }

        let lines = text.components(separatedBy: .newlines)
        var entries: [TextLineEntry] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                entries.append(.blank)
                index += 1
                continue
            }

            if let table = parseTableBlock(startingAt: index, in: lines) {
                entries.append(.table(headers: table.headers, alignments: table.alignments, rows: table.rows))
                index += table.consumed
                continue
            }

            if let delimiter = startDelimiter(for: trimmed) {
                var blockLines: [String] = [line]
                var cursor = index + 1
                while cursor < lines.count {
                    let nextLine = lines[cursor]
                    blockLines.append(nextLine)
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    if closes(nextTrimmed, matching: delimiter) {
                        cursor += 1
                        break
                    }
                    cursor += 1
                }
                entries.append(.mathBlock(blockLines.joined(separator: "\n")))
                index = cursor
                continue
            }

            if let level = headingLevel(for: trimmed) {
                let content = String(trimmed.drop(while: { $0 == "#" || $0 == " " }))
                entries.append(.heading(level: level, content: content))
                index += 1
                continue
            }

            if let (marker, content) = parseBulletLine(line) {
                entries.append(.bullet(marker: marker, content: content))
                index += 1
                continue
            }

            entries.append(.text(line))
            index += 1
        }

        return entries
    }

    @ViewBuilder
    private func tableView(headers: [String], alignments: [TableColumnAlignment], rows: [[String]]) -> some View {
        let columns: [GridItem] = alignments.map { alignment in
            GridItem(.flexible(), spacing: 12, alignment: alignment.gridAlignment)
        }

        VStack(spacing: 0) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                    MathRichText(source: header, bodyFont: tableHeaderFont)
                        .font(tableHeaderFont)
                        .multilineTextAlignment(alignments[index].textAlignment)
                        .frame(maxWidth: .infinity, alignment: alignments[index].frameAlignment)
                }
            }
            .padding(.bottom, rows.isEmpty ? 0 : 10)

            if !rows.isEmpty {
                Divider()
                    .padding(.bottom, 10)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, value in
                        MathRichText(source: value, bodyFont: chatBodyFont)
                            .font(chatBodyFont)
                            .multilineTextAlignment(alignments[columnIndex].textAlignment)
                            .frame(maxWidth: .infinity, alignment: alignments[columnIndex].frameAlignment)
                    }
                }
                if rowIndex < rows.count - 1 {
                    Divider()
                        .padding(.vertical, 10)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tableBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tableBorderColor, lineWidth: 0.5)
        )
    }

    private func parseTableBlock(startingAt startIndex: Int, in lines: [String]) -> (consumed: Int, headers: [String], alignments: [TableColumnAlignment], rows: [[String]])? {
        guard let headerCells = parseTableRow(lines[startIndex]) else { return nil }
        let separatorIndex = startIndex + 1
        guard separatorIndex < lines.count,
              let alignments = parseTableAlignments(lines[separatorIndex], expectedCount: headerCells.count) else {
            return nil
        }

        var rows: [[String]] = []
        var cursor = separatorIndex + 1

        while cursor < lines.count {
            let candidate = lines[cursor]
            if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            guard let cells = parseTableRow(candidate), cells.count == headerCells.count else {
                break
            }
            rows.append(cells)
            cursor += 1
        }

        let consumed = 1 + 1 + rows.count
        return (consumed, headerCells, alignments, rows)
    }

    private func parseTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }

        var segments = trimmed.split(separator: "|", omittingEmptySubsequences: false).map { segment in
            segment.trimmingCharacters(in: .whitespaces)
        }

        if let first = segments.first, first.isEmpty { segments.removeFirst() }
        if let last = segments.last, last.isEmpty { segments.removeLast() }

        guard segments.count >= 2 else { return nil }

        // Require at least one non-empty column so we don't treat inline pipes as tables
        guard segments.contains(where: { !$0.isEmpty }) else { return nil }

        return segments
    }

    private func parseTableAlignments(_ line: String, expectedCount: Int) -> [TableColumnAlignment]? {
        guard let rawColumns = parseTableRow(line), rawColumns.count == expectedCount else { return nil }

        var alignments: [TableColumnAlignment] = []
        for column in rawColumns {
            let trimmed = column.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("-") else { return nil }

            let leadingColon = trimmed.hasPrefix(":")
            let trailingColon = trimmed.hasSuffix(":")
            let dashPortion = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashPortion.isEmpty, dashPortion.allSatisfy({ $0 == "-" }) else { return nil }

            let alignment: TableColumnAlignment
            if leadingColon && trailingColon {
                alignment = .center
            } else if trailingColon {
                alignment = .trailing
            } else {
                alignment = .leading
            }
            alignments.append(alignment)
        }

        return alignments
    }

    private func headingLevel(for line: String) -> Int? {
        // Recognize ATX-style headings: '#', '##', '###', up to 6
        guard line.first == "#" else { return nil }
        var count = 0
        for ch in line {
            if ch == "#" { count += 1 } else { break }
        }
        // Must have a space after hashes to be a heading
        if count >= 1 && count <= 6 {
            let idx = line.index(line.startIndex, offsetBy: count)
            if idx < line.endIndex && line[idx].isWhitespace { return count }
        }
        return nil
    }
    
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }
    
    // Normalizes inline lists like " ...  1. Item  2. Item ..." to place each
    // item on its own line. Our rich text engine preserves paragraph breaks
    // only for double newlines, so we emit "\n\n" here.
    private func normalizeListFormatting(_ text: String) -> String {
        var s = text
        func replace(_ pattern: String, _ template: String) {
            if let rx = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                s = rx.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
            }
        }
        // Insert paragraph break before inline numbered items like "  2.", "  3)" or "  4]"
        replace(#"(?:(?<=^)|(?<=\n)|(?<=[:;]))\s*(?=\d{1,3}[\.\)\]]\s)"#, "\n\n")
        // Insert paragraph break before inline bullet markers like " - ", " * ", " + ", or " • "
        replace(#"(?:(?<=^)|(?<=\n)|(?<=[:;]))\s*(?=[\-\*\+•]\s)"#, "\n\n")
        // Ensure a single newline before a list marker becomes a paragraph break
        replace(#"\n(?=\s*(?:\d{1,3}[\.\)\]]\s|[\-\*\+•]\s))"#, "\n\n")
        // If a list follows a colon, break the line after the colon
        replace(#":\s+(?=(?:\d{1,3}[\.\)\]]\s|[\-\*\+•]\s))"#, ":\n\n")
        // Collapse any 3+ consecutive newlines into a double newline
        replace(#"\n{3,}"#, "\n\n")
        return s
    }
    
    // MARK: - List parsing helpers
    private struct TextBlock {
        let content: String
        let isList: Bool
        let marker: String?
    }
    
    private func parseTextBlocks(_ text: String) -> [TextBlock] {
        var blocks: [TextBlock] = []
        let lines = text.components(separatedBy: .newlines)
        var currentTextBlock = ""
        
        for line in lines {
            if let (marker, content) = parseBulletLine(line) {
                // If we have accumulated text, add it as a text block
                if !currentTextBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(TextBlock(content: currentTextBlock, isList: false, marker: nil))
                    currentTextBlock = ""
                }
                // Add the list item
                blocks.append(TextBlock(content: content, isList: true, marker: marker))
            } else {
                // Accumulate non-list lines
                currentTextBlock += (currentTextBlock.isEmpty ? "" : "\n") + line
            }
        }
        
        // Add any remaining text
        if !currentTextBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(TextBlock(content: currentTextBlock, isList: false, marker: nil))
        }
        
        return blocks
    }
    
    private func parseListItems(_ text: String) -> [(marker: String, content: String)] {
        var items: [(String, String)] = []
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            if let item = parseBulletLine(line) {
                items.append(item)
            }
        }
        
        return items
    }
    
    private func parseBulletLine(_ line: String) -> (marker: String, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // Unordered bullets: -, *, +, •
        if trimmed.hasPrefix("- ") { return ("•", String(trimmed.dropFirst(2))) }
        if trimmed.hasPrefix("* ") { return ("•", String(trimmed.dropFirst(2))) }
        if trimmed.hasPrefix("+ ") { return ("•", String(trimmed.dropFirst(2))) }
        if trimmed.hasPrefix("• ") { return ("•", String(trimmed.dropFirst(2))) }
        
        // Ordered bullets: 1. 2) 3]
        if let dotIdx = trimmed.firstIndex(of: "."), dotIdx > trimmed.startIndex {
            let prefix = String(trimmed[..<dotIdx])
            if Int(prefix) != nil, trimmed[dotIdx...].hasPrefix(". ") {
                return (prefix + ".", String(trimmed[trimmed.index(dotIdx, offsetBy: 2)...]))
            }
        }
        if let parenIdx = trimmed.firstIndex(of: ")"), parenIdx > trimmed.startIndex {
            let prefix = String(trimmed[..<parenIdx])
            if Int(prefix) != nil, trimmed[parenIdx...].hasPrefix(") ") {
                return (prefix + ")", String(trimmed[trimmed.index(parenIdx, offsetBy: 2)...]))
            }
        }
        if let bracketIdx = trimmed.firstIndex(of: "]"), bracketIdx > trimmed.startIndex {
            let prefix = String(trimmed[..<bracketIdx])
            if Int(prefix) != nil, trimmed[bracketIdx...].hasPrefix("] ") {
                return (prefix + "]", String(trimmed[trimmed.index(bracketIdx, offsetBy: 2)...]))
            }
        }
        
        return nil
    }
    
    private func extractRemainingText(from text: String, afterListItems items: [(String, String)]) -> String {
        var remaining = ""
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            if parseBulletLine(line) == nil {
                remaining += (remaining.isEmpty ? "" : "\n") + line
            }
        }
        
        return remaining
    }
    
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false
    
    // MARK: - Code block rendering
    private struct CodeBlockView: View {
        let code: String
        let language: String?
        @State private var copied = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Header with language label and copy button
                HStack {
                    if let lang = language, !lang.isEmpty {
                        Text(lang)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
#if os(iOS)
                        UIPasteboard.general.string = code
#elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
#endif
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                            Text(copied ? "Copied!" : "Copy")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                // Code content with darker background
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
#if os(macOS)
                        .textSelection(.enabled)
#endif
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.systemGray6))
                .adaptiveCornerRadius(.small)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .background(Color(.systemGray5))
            .adaptiveCornerRadius(.medium)
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        }
    }
    
    // Helper to find matching closing brace for a JSON object, honoring strings and escapes
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
            if char == "\"" { inString.toggle() }
            if !inString {
                if char == "{" { braceCount += 1 }
                else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 { return idx }
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
    
    private var chatBodyFont: Font {
#if os(macOS)
        return .system(size: 16, weight: .regular)
#else
        return .body
#endif
    }

    private var tableHeaderFont: Font {
#if os(macOS)
        return .system(size: 15, weight: .semibold)
#else
        return .system(size: 15, weight: .semibold)
#endif
    }

    private var tableBackgroundColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.06)
        }
        return Color.primary.opacity(0.05)
    }

    private var tableBorderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.08)
    }

    var bubbleColor: Color {
        if msg.role == "🧑‍💻" {
#if os(macOS)
            let accentOpacity: Double = colorScheme == .dark ? 0.3 : 0.22
            return Color.accentColor.opacity(accentOpacity)
#else
            return Color.accentColor.opacity(0.2)
#endif
        }
#if os(macOS)
        if colorScheme == .dark {
            return Color(uiColor: UIColor.controlBackgroundColor.withAlphaComponent(0.55))
        } else {
            return Color(uiColor: UIColor.textBackgroundColor)
        }
#else
        return Color(.secondarySystemBackground)
#endif
    }
    
    @ViewBuilder
    private func imagesView(paths: [String]) -> some View {
        let thumbSize = CGSize(width: 96, height: 96)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(paths.prefix(5).enumerated()), id: \.offset) { _, p in
                    let img = ImageThumbnailCache.shared.thumbnail(for: p, pointSize: thumbSize)
                    ZStack {
                        if let ui = img {
                            Image(platformImage: ui)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle().fill(Color.secondary.opacity(0.15))
                                .overlay(ProgressView().scaleEffect(0.6))
                        }
                    }
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .clipped()
                    .cornerRadius(12)
                    .drawingGroup(opaque: false)
                    .contentShape(Rectangle())
                    .onTapGesture { expandedImagePath = p }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
    }

    private struct AttachmentPreview: View {
        let path: String
        let onClose: () -> Void
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.95).ignoresSafeArea()
#if canImport(UIKit)
                if let ui = UIImage(contentsOfFile: path) {
                    Image(platformImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.001).ignoresSafeArea())
                } else {
                    Text("Unable to load image").foregroundColor(.white)
                }
#else
                if let ns = NSImage(contentsOfFile: path) {
                    Image(nsImage: ns)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.001).ignoresSafeArea())
                } else {
                    Text("Unable to load image").foregroundColor(.white)
                }
#endif
                HStack {
                    Spacer()
                    Button(action: { onClose(); dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onClose(); dismiss() }
        }
    }

    private func displayedToolCall(_ call: ChatVM.Msg.ToolCall) -> ChatVM.Msg.ToolCall {
        guard call.toolName == "noema.web.retrieve" else { return call }

        if let err = msg.webError {
            return ChatVM.Msg.ToolCall(
                id: call.id,
                toolName: call.toolName,
                displayName: call.displayName,
                iconName: call.iconName,
                requestParams: call.requestParams,
                result: nil,
                error: err,
                timestamp: call.timestamp
            )
        }

        guard let hits = msg.webHits, !hits.isEmpty else { return call }

        let hitsArray: [[String: Any]] = hits.map { hit in
            [
                "title": hit.title,
                "url": hit.url,
                "snippet": hit.snippet,
                "engine": hit.engine,
                "score": hit.score
            ]
        }

        if let data = try? JSONSerialization.data(withJSONObject: hitsArray, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            return ChatVM.Msg.ToolCall(
                id: call.id,
                toolName: call.toolName,
                displayName: call.displayName,
                iconName: call.iconName,
                requestParams: call.requestParams,
                result: jsonString,
                error: nil,
                timestamp: call.timestamp
            )
        }

        return call
    }
    
    private struct RenderEntry: Identifiable {
        enum Kind {
            case text(String)
            case code(code: String, language: String?)
            case thinkExisting(key: String)
            case thinkNew(text: String, done: Bool, key: String)
            case tool(ChatVM.Msg.ToolCall)
            case postToolWait
        }

        let id: String
        let kind: Kind
        let topPadding: CGFloat
        let bottomPadding: CGFloat

        init(id: String, kind: Kind, topPadding: CGFloat, bottomPadding: CGFloat = 0) {
            self.id = id
            self.kind = kind
            self.topPadding = topPadding
            self.bottomPadding = bottomPadding
        }
    }

    @ViewBuilder
    private func piecesView(_ pieces: [ChatVM.Piece]) -> some View {
        let thinkOrdinals: [Int?] = {
            var ordinals = Array(repeating: Int?.none, count: pieces.count)
            var counter = 0
            for idx in pieces.indices {
                if pieces[idx].isThink {
                    ordinals[idx] = counter
                    counter += 1
                }
            }
            return ordinals
        }()

        let renderEntries: [RenderEntry] = {
            var results: [RenderEntry] = []
            var renderedToolCallIDs = Set<UUID>()

            for idx in pieces.indices {
                let piece = pieces[idx]
                let prevIsThink = idx > 0 ? pieces[idx - 1].isThink : false
                let prevIsTool = idx > 0 ? pieces[idx - 1].isTool : false

                switch piece {
                case .text(let t):
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let topPadding: CGFloat = (prevIsThink || prevIsTool) ? 2 : 4
                    results.append(
                        RenderEntry(
                            id: "text-\(msg.id.uuidString)-\(idx)",
                            kind: .text(t),
                            topPadding: topPadding
                        )
                    )
                case .code(let code, let language):
                    results.append(
                        RenderEntry(
                            id: "code-\(msg.id.uuidString)-\(idx)",
                            kind: .code(code: code, language: language),
                            topPadding: 4
                        )
                    )
                case .think(let t, let done):
                    guard let thinkOrdinalIndex = thinkOrdinals[idx] else { continue }
                    let thinkKey = "message-\(msg.id.uuidString)-think-\(thinkOrdinalIndex)"

                    if vm.rollingThoughtViewModels[thinkKey] != nil {
                        results.append(
                            RenderEntry(
                                id: "think-existing-\(thinkKey)",
                                kind: .thinkExisting(key: thinkKey),
                                topPadding: 4
                            )
                        )
                    } else {
                        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        results.append(
                            RenderEntry(
                                id: "think-new-\(thinkKey)",
                                kind: .thinkNew(text: t, done: done, key: thinkKey),
                                topPadding: 4
                            )
                        )
                    }
                case .tool(let toolIndex):
                    guard let toolCalls = msg.toolCalls,
                          toolCalls.indices.contains(toolIndex) else { continue }

                    let originalCall = toolCalls[toolIndex]
                    let call = displayedToolCall(originalCall)
                    guard renderedToolCallIDs.insert(call.id).inserted else { continue }

                    results.append(
                        RenderEntry(
                            id: "tool-\(call.id.uuidString)",
                            kind: .tool(call),
                            topPadding: 4,
                            bottomPadding: 2
                        )
                    )
                }
            }
            // Append a small spinner after the last tool call while waiting
            // for the post-tool continuation to start streaming tokens.
            if msg.postToolWaiting, pieces.contains(where: { $0.isTool }) {
                results.append(
                    RenderEntry(
                        id: "post-tool-wait-\(msg.id.uuidString)",
                        kind: .postToolWait,
                        topPadding: 4,
                        bottomPadding: 2
                    )
                )
            }
            return results
        }()

        VStack(alignment: .leading, spacing: 0) {
            ForEach(renderEntries) { entry in
                switch entry.kind {
                case .text(let text):
                    renderTextOrList(text)
                        .padding(.top, entry.topPadding)
                case .code(let code, let language):
                    CodeBlockView(code: code, language: language)
                        .padding(.top, entry.topPadding)
                case .thinkExisting(let key):
                    if let viewModel = vm.rollingThoughtViewModels[key] {
                        RollingThoughtBox(viewModel: viewModel)
                            .padding(.top, entry.topPadding)
                    }
                case .thinkNew(let text, let done, let key):
                    let tempVM = RollingThoughtViewModel()
                    RollingThoughtBox(viewModel: tempVM)
                        .padding(.top, entry.topPadding)
                        .onAppear {
                            DispatchQueue.main.async {
                                tempVM.fullText = text
                                tempVM.updateRollingLines()
                                tempVM.phase = done ? .complete : .streaming
                                if vm.rollingThoughtViewModels[key] == nil {
                                    vm.rollingThoughtViewModels[key] = tempVM
                                }
                            }
                        }
                case .tool(let call):
                    ToolCallView(toolCall: call)
                        .padding(.top, entry.topPadding)
                        .padding(.bottom, entry.bottomPadding)
                case .postToolWait:
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.top, entry.topPadding)
                        .padding(.bottom, entry.bottomPadding)
                }
            }
        }
    }
    
    private func copyMessageToPasteboard() {
        let copyPayload = copyableMessageText()
#if os(iOS) || os(visionOS)
        UIPasteboard.general.string = copyPayload
#if os(iOS)
        Haptics.impact(.light)
#endif
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyPayload, forType: .string)
#endif
        copiedMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedMessage = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if copiedMessage {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showCopyPopup = false
                }
            }
        }
    }

    private func copyableMessageText() -> String {
        let pieces = parse(msg.text, toolCalls: msg.toolCalls)
        var sections: [String] = []
        sections.reserveCapacity(pieces.count)

        var textAccumulator = ""

        func flushTextAccumulator() {
            let trimmed = textAccumulator.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let sanitized = textAccumulator.trimmingCharacters(in: .newlines)
                sections.append(sanitized)
            }
            textAccumulator.removeAll(keepingCapacity: true)
        }

        for piece in pieces {
            switch piece {
            case .text(let text):
                textAccumulator.append(text)
            case .code(let code, let language):
                flushTextAccumulator()
                let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedCode.isEmpty else { continue }
                let lang = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let header = lang.isEmpty ? "```" : "```\(lang)"
                var block = header + "\n" + code
                if !code.hasSuffix("\n") {
                    block.append("\n")
                }
                block.append("```")
                sections.append(block)
            case .think, .tool:
                continue
            }
        }
        flushTextAccumulator()

        let combined = sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !combined.isEmpty {
            return combined
        }

        return msg.text
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func datasetBadge(_ name: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dataset")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.8)
        )
    }

#if os(visionOS)
    private func pinMessage() {
        guard let sessionID = vm.activeSessionID else { return }
        let note = pinnedStore.pin(message: msg, in: sessionID)
        openWindow(id: VisionSceneID.pinnedCardWindow, value: note.id)
    }
#endif
    
    @ViewBuilder
    private func bubbleView(
        _ pieces: [ChatVM.Piece],
        hasWebRetrieveCall: Bool,
        isSpotlighted: Bool
    ) -> some View {
        let trimmedText = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasExternalToolContent = (
            (msg.toolCalls?.isEmpty == false) ||
            msg.usedWebSearch == true ||
            hasWebRetrieveCall
        )
        let shouldShowTokenLoadingIndicator =
            msg.role == "🤖" &&
            msg.streaming &&
            trimmedText.isEmpty &&
            !hasExternalToolContent

        VStack(alignment: .leading, spacing: 4) {
            if msg.role == "🧑‍💻", let datasetName = datasetDisplayName {
                datasetBadge(datasetName)
            }

            if shouldShowTokenLoadingIndicator {
                HStack {
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }

            if !pieces.isEmpty {
                piecesView(pieces)
            }
        }
        .padding(12)
        .frame(
            maxWidth: currentDeviceWidth() * 0.85,
            alignment: msg.role == "🧑‍💻" ? .trailing : .leading
        )
        .background(bubbleColor)
        .adaptiveCornerRadius(.large)
        .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                .stroke(Color.accentColor.opacity(isSpotlighted ? 0.9 : 0), lineWidth: isSpotlighted ? 3 : 0)
        )
#if os(macOS)
        .textSelection(.enabled)
#endif
        .animation(.easeInOut(duration: 0.2), value: isSpotlighted)
    }

    @ViewBuilder
    private func messageContainer(
        pieces: [ChatVM.Piece],
        hasWebRetrieveCall: Bool,
        isSpotlighted: Bool
    ) -> some View {
        messageContainerBody(
            pieces: pieces,
            hasWebRetrieveCall: hasWebRetrieveCall,
            isSpotlighted: isSpotlighted
        )
#if os(macOS)
        .textSelection(.enabled)
#endif
    }

    private func messageContainerBody(
        pieces: [ChatVM.Piece],
        hasWebRetrieveCall: Bool,
        isSpotlighted: Bool
    ) -> some View {
        VStack(alignment: msg.role == "🧑‍💻" ? .trailing : .leading, spacing: 2) {
            if let paths = msg.imagePaths, !paths.isEmpty {
                imagesView(paths: paths)
            }

            HStack {
                if msg.role == "🧑‍💻" { Spacer() }

                bubbleView(pieces, hasWebRetrieveCall: hasWebRetrieveCall, isSpotlighted: isSpotlighted)

                if msg.role != "🧑‍💻" { Spacer() }
            }

            if isAdvancedMode, msg.role == "🤖", let p = msg.perf {
                let text = String(
                    format: "%.2f tok/sec · %d tokens · %.2fs to first token",
                    p.avgTokPerSec,
                    p.tokenCount,
                    p.timeToFirst
                )
                Text(text)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(msg.role == "🧑‍💻" ? .trailing : .leading, 12)
            }

            Text(msg.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(msg.role == "🧑‍💻" ? .trailing : .leading, 12)

            if let citations = msg.citations, !citations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass").font(.caption)
                            Text("\(citations.count)")
                                .font(.caption2).bold()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                        ForEach(Array(citations.enumerated()), id: \.offset) { idx, citation in
                            CitationButton(index: idx + 1, text: citation.text, source: citation.source)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(msg.role == "🧑‍💻" ? .trailing : .leading, 12)
            } else if let ctx = msg.retrievedContext, !ctx.isEmpty {
                let parts = ctx
                    .components(separatedBy: "\n\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass").font(.caption)
                            Text("\(parts.count)")
                                .font(.caption2).bold()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                        ForEach(Array(parts.enumerated()), id: \.offset) { idx, t in
                            CitationButton(index: idx + 1, text: t, source: nil)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(msg.role == "🧑‍💻" ? .trailing : .leading, 12)
            }
        }
        .macWindowDragDisabled()
#if os(macOS)
        .environment(\.messageHoverCopySuppression, $suppressHoverCopy)
#endif
    }

    @ViewBuilder
    private func popupContainer(
        pieces: [ChatVM.Piece],
        hasWebRetrieveCall: Bool,
        isSpotlighted: Bool
    ) -> some View {
        HStack {
            if msg.role == "🧑‍💻" { Spacer() }

            VStack(alignment: .leading, spacing: 12) {
                messageContainer(
                    pieces: pieces,
                    hasWebRetrieveCall: hasWebRetrieveCall,
                    isSpotlighted: isSpotlighted
                )
                .allowsHitTesting(false)
                .scaleEffect(1.02)
                
                Button(action: { copyMessageToPasteboard() }) {
                    Label(copiedMessage ? "Copied!" : "Copy", systemImage: copiedMessage ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 12)
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCopyPopup = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: currentDeviceWidth() * 0.9)
            
            if msg.role != "🧑‍💻" { Spacer() }
        }
        .padding(.horizontal, 12)
        .transition(.scale.combined(with: .opacity))
    }
    
    var body: some View {
        let pieces = parse(msg.text, toolCalls: msg.toolCalls)
        let hasWebRetrieveCall = msg.toolCalls?.contains { $0.toolName == "noema.web.retrieve" } ?? false
        
        let isSpotlighted = vm.spotlightMessageID == msg.id

        ZStack(alignment: .center) {
            messageContainer(
                pieces: pieces,
                hasWebRetrieveCall: hasWebRetrieveCall,
                isSpotlighted: isSpotlighted
            )
            .opacity(showCopyPopup ? 0.25 : 1)
            .allowsHitTesting(!showCopyPopup)

            if showCopyPopup {
                ZStack {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showCopyPopup = false
                            }
                        }
                    
                    popupContainer(
                        pieces: pieces,
                        hasWebRetrieveCall: hasWebRetrieveCall,
                        isSpotlighted: isSpotlighted
                    )
                }
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == "🧑‍💻" ? .trailing : .leading)
#if os(iOS)
        .onLongPressGesture(minimumDuration: 0.45) {
            copiedMessage = false
            performMediumImpact()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                showCopyPopup = true
            }
        }
#endif
#if os(macOS)
        .overlay(alignment: msg.role == "🧑‍💻" ? .bottomTrailing : .bottomLeading) {
            if hoverCopyVisible && !showCopyPopup && !suppressHoverCopy {
                Button(action: copyMessageToPasteboard) {
                    Label(copiedMessage ? "Copied!" : "Copy", systemImage: copiedMessage ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(Color.accentColor)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Copy message")
                .offset(y: 20)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                hoverCopyVisible = hovering
            }
            if !hovering {
                suppressHoverCopy = false
            }
        }
#endif
#if os(visionOS)
        .overlay(alignment: msg.role == "🧑‍💻" ? .bottomTrailing : .bottomLeading) {
            if showInteractionOptions && !showCopyPopup {
                HStack(spacing: 10) {
                    Button(action: copyMessageToPasteboard) {
                        Image(systemName: copiedMessage ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy message")

                    Button(action: pinMessage) {
                        Image(systemName: "pin")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pin message")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .offset(y: 26)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                hoverActive = hovering
                if hovering {
                    showInteractionOptions = true
                } else if !isPressingMessage {
                    showInteractionOptions = false
                }
            }
        }
        .onChangeCompat(of: isPressingMessage) { _, pressing in
            withAnimation(.easeInOut(duration: 0.18)) {
                if pressing {
                    showInteractionOptions = true
                } else if !hoverActive {
                    showInteractionOptions = false
                }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .updating($isPressingMessage) { current, state, _ in
                    state = current
                }
        )
#endif
        .onChangeCompat(of: showCopyPopup) { _, newValue in
            if !newValue {
                copiedMessage = false
            }
#if os(visionOS)
            if newValue {
                showInteractionOptions = false
            }
#endif
        }
        .onChangeCompat(of: msg.text) { _, _ in
            if showCopyPopup {
                copiedMessage = false
            }
        }
        .onChangeCompat(of: vm.msgs) { _, _ in
            if showCopyPopup {
                showCopyPopup = false
            }
        }
#if os(iOS) || os(visionOS)
        .fullScreenCover(isPresented: Binding(get: { expandedImagePath != nil }, set: { if !$0 { expandedImagePath = nil } })) {
            if let p = expandedImagePath {
                AttachmentPreview(path: p) { expandedImagePath = nil }
            }
        }
#else
        .sheet(isPresented: Binding(get: { expandedImagePath != nil }, set: { if !$0 { expandedImagePath = nil } })) {
            if let p = expandedImagePath {
                AttachmentPreview(path: p) { expandedImagePath = nil }
                    .frame(minWidth: 560, minHeight: 420)
            }
        }
#endif
#if os(visionOS)
        .contextMenu {
            Button {
                copyMessageToPasteboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                pinMessage()
            } label: {
                Label("Pin", systemImage: "pin")
            }
        }
#endif
    }

    struct ChatView: View {
        @EnvironmentObject var vm: ChatVM
        @EnvironmentObject var modelManager: AppModelManager
        @EnvironmentObject var datasetManager: DatasetManager
        @EnvironmentObject var tabRouter: TabRouter
        @EnvironmentObject var walkthrough: GuidedWalkthroughManager
        @AppStorage("isAdvancedMode") private var isAdvancedMode = false
        @FocusState private var inputFocused: Bool
        @State private var showSidebar = false
        @State private var showPercent = false
        @State private var sessionToDelete: ChatVM.Session?
        @State private var shouldAutoScrollToBottom: Bool = true
        @State private var lastHapticMessageID: UUID?
        // Suggestion overlay state
        @State private var suggestionTriplet: [String] = ChatSuggestions.nextThree()
        @State private var suggestionsSessionID: UUID?
        @State private var showModelRequiredAlert = false
        @State private var quickLoadInProgress: LocalModel.ID?
#if os(macOS)
        @EnvironmentObject private var macChatChrome: MacChatChromeState
        @State private var advancedSettings = ModelSettings()
        @State private var suppressSidebarSave = false
        @State private var datasetPillHovered = false
#endif
        
        
        private struct ChatInputBox: View {
            @Binding var text: String
            var focus: FocusState<Bool>.Binding
            @Binding var showModelRequiredAlert: Bool
            let send: () -> Void
            let stop: () -> Void
            let canStop: Bool
            @EnvironmentObject var vm: ChatVM
            @EnvironmentObject var modelManager: AppModelManager
            @EnvironmentObject var tabRouter: TabRouter
            @State private var showSmallCtxAlert: Bool = false
            @State private var measuredHeight: CGFloat = 0
            private struct InputHeightPreferenceKey: PreferenceKey {
                static var defaultValue: CGFloat { 0 }
                static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
            }
            // Keep the input aligned with surrounding buttons; slightly shorter on macOS.
            private let controlHeight: CGFloat = {
#if os(macOS)
                return 40
#else
                return 42
#endif
            }()
            private let inputMaxHeight: CGFloat = {
#if os(macOS)
                return 132
#else
                return 124
#endif
            }()
            private let inputVerticalPadding: CGFloat = {
#if os(macOS)
                return 4
#else
                return 4
#endif
            }()
            private let inputOuterVerticalPadding: CGFloat = {
#if os(macOS)
                return 8
#else
                return 2
#endif
            }()

            private var resolvedHeight: CGFloat {
                let minContent = max(controlHeight - (inputOuterVerticalPadding * 2), 0)
                let maxContent = max(inputMaxHeight - (inputOuterVerticalPadding * 2), minContent)
                let clamped = min(max(measuredHeight, minContent), maxContent)
                return clamped
            }

            private var measurementText: String {
                text.isEmpty ? "Ask…" : text + " "
            }
            
            
            var body: some View {
                HStack(spacing: 8) {
#if os(macOS)
                    WebSearchButton()
                        .guideHighlight(.chatWebSearch)
                        .padding(.trailing, 2)
                    if UIConstants.showMultimodalUI && vm.supportsImageInput {
                        VisionAttachmentButton()
                            .padding(.trailing, 2)
                    }
#endif
#if os(iOS) || os(visionOS)
                    WebSearchButton()
                        .guideHighlight(.chatWebSearch)
                    if UIConstants.showMultimodalUI && vm.supportsImageInput {
                        VisionAttachmentButton()
                    }
#endif
                    let isChatReady = (vm.modelLoaded || modelManager.loadedModel != nil || modelManager.activeRemoteSession != nil)
                    VStack(spacing: 8) {
                        // Images displayed above the text field
                        if UIConstants.showMultimodalUI && vm.supportsImageInput && !vm.pendingImageURLs.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(vm.pendingImageURLs.prefix(5).enumerated()), id: \.offset) { idx, url in
                                        let thumbnail = vm.pendingThumbnail(for: url)
                                        ZStack(alignment: .topTrailing) {
                                            Group {
                                                if let ui = thumbnail {
                                                    Image(platformImage: ui)
                                                        .resizable()
                                                        .scaledToFill()
                                                } else {
                                                    // Lightweight placeholder while any thumb is missing
                                                    Rectangle()
                                                        .fill(Color.secondary.opacity(0.15))
                                                        .overlay(
                                                            ProgressView().scaleEffect(0.6)
                                                        )
                                                }
                                            }
                                            .frame(width: 80, height: 80)
                                            .clipped()
                                            .cornerRadius(12)

                                            Button(action: { vm.removePendingImage(at: idx) }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 16))
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                            }
                                            .offset(x: 6, y: -6)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: UIConstants.largeCornerRadius, style: .continuous)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        
                        // Input area with vision attachments and multi-line text entry
                        HStack(spacing: 12) {
                            ZStack(alignment: .topLeading) {
#if os(iOS) || os(visionOS)
                                TextField("Ask…", text: $text, axis: .vertical)
                                    .focused(focus)
                                    .disabled(!isChatReady)
                                    .textInputAutocapitalization(.sentences)
                                    .lineLimit(1...6)
                                    .textFieldStyle(.plain)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(maxHeight: resolvedHeight, alignment: .topLeading)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, inputVerticalPadding)
                                    .accessibilityLabel(Text("Message input"))
                                    .accessibilityHint("Double-tap Return to insert a new line. Use the Send button to send.")
#else
                                TextEditor(text: $text)
                                    .focused(focus)
                                    .disabled(!isChatReady)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(maxHeight: resolvedHeight, alignment: .topLeading)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, inputVerticalPadding)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .accessibilityLabel(Text("Message input"))
                                    .accessibilityHint("Double-tap Return to insert a new line. Use the Send button to send.")

                                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Ask…")
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, inputVerticalPadding + 2)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
#endif
                                // Invisible measurement text keeps the control compact until content grows.
                                Text(measurementText)
                                    .font(.body)
                                    .lineLimit(nil)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, inputVerticalPadding)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear.preference(key: InputHeightPreferenceKey.self, value: proxy.size.height)
                                        }
                                    )
                                    .hidden()

                                if !isChatReady {
                                    RoundedRectangle(cornerRadius: UIConstants.extraLargeCornerRadius, style: .continuous)
                                        .fill(Color.clear)
                                        .contentShape(
                                            RoundedRectangle(cornerRadius: UIConstants.extraLargeCornerRadius, style: .continuous)
                                        )
                                        .onTapGesture {
                                            focus.wrappedValue = false
                                            showModelRequiredAlert = true
                                        }
                                }
                            }
                            .onPreferenceChange(InputHeightPreferenceKey.self) { measuredHeight = $0 }
                            .padding(.horizontal, 10)
                            .padding(.vertical, inputOuterVerticalPadding)
                            .frame(minHeight: controlHeight,
                                   maxHeight: inputMaxHeight,
                                   alignment: .topLeading)
                            .frame(height: resolvedHeight + (inputOuterVerticalPadding * 2), alignment: .topLeading)
                            .glassPill()
                            .frame(maxWidth: .infinity)
                        }
                    }
                    if canStop {
                        Button(action: stop) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.red)
                                )
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain) // Avoid default gray button chrome behind the custom red pill
                    } else {
                        Button(action: {
                            guard isChatReady else {
                                showModelRequiredAlert = true
                                focus.wrappedValue = false
                                return
                            }
                            guard !vm.isStreamingInAnotherSession else {
                                vm.crossSessionSendBlocked = true
                                focus.wrappedValue = false
                                return
                            }
                            if UIConstants.showMultimodalUI && vm.supportsImageInput && !vm.pendingImageURLs.isEmpty && vm.contextLimit < 5000 {
                                showSmallCtxAlert = true
                                return
                            }
                            send()
                            text = ""
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.accentColor)
                                )
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isChatReady || vm.isStreamingInAnotherSession || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                // Avoid animating the entire input row on every keystroke,
                // which caused attachment thumbnails to flicker.
                // If animation is desired for send/stop swaps, animate those states specifically.
                .alert("Finish current response", isPresented: Binding(
                    get: { vm.crossSessionSendBlocked },
                    set: { vm.crossSessionSendBlocked = $0 }
                )) {
                    Button("OK", role: .cancel) { vm.crossSessionSendBlocked = false }
                } message: {
                    Text("Wait for the response in your other chat to finish before sending a new message.")
                }
                .alert("Small context may cause image crash", isPresented: $showSmallCtxAlert) {
                    Button("Send Anyway") {
                        send()
                        text = ""
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Context length is under 5000 tokens. With images and multi-sequence decoding (n_seq_max=16), per-sequence memory can be too small, leading to a crash. Increase context to at least 8192 in Model Settings.")
                }
                .alert("Load a model to chat", isPresented: $showModelRequiredAlert) {
                    Button("Open Explore") {
                        tabRouter.selection = .explore
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Load a local model before chatting. You can download one from the Explore tab or load a model you've already installed.")
                }
            }

        }
        
        var body: some View {
            NavigationStack {
#if os(macOS)
                macChatContainer
#else
                ZStack(alignment: .leading) {
                    chatContent
                        .guideHighlight(.chatCanvas)
                    if showSidebar {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation { showSidebar = false } }
                        sidebar
                            .frame(width: currentDeviceWidth() * 0.48)
                            .transition(.move(edge: .leading))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
#if os(iOS) || os(visionOS)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation { showSidebar.toggle() }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .guideHighlight(.chatSidebarButton)
                    }
                    ToolbarItem(placement: .principal) {
                        modelHeader
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { vm.startNewSession() } label: { Image(systemName: "plus") }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .guideHighlight(.chatNewChatButton)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
#endif
#endif
            }
#if os(macOS)
            .navigationTitle("Chat")
#endif
            .alert(item: $datasetManager.embedAlert) { info in
                Alert(title: Text(info.message))
            }
            .overlay(alignment: .top) {
                if let active = modelManager.activeDataset,
                   datasetManager.indexingDatasetID == active.datasetID {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        let status = datasetManager.processingStatus[active.datasetID]
                        if let s = status, s.stage != .completed {
                            let etaStr: String = {
                                if let e = s.etaSeconds, e > 0 { return String(format: "~%dm %02ds", Int(e)/60, Int(e)%60) }
                                return "…"
                            }()
                            Text("Indexing: \(Int(s.progress * 100))% · \(etaStr)").font(.caption2)
                        } else {
                            Text("Indexing dataset…").font(.caption2)
                        }
                    }
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
                }
            }
#if os(macOS)
            .onAppear { syncSidebarSettings() }
            .onChange(of: modelManager.loadedModel?.id) { _ in syncSidebarSettings() }
            .onReceive(modelManager.$modelSettings) { _ in syncSidebarSettings() }
            .onChange(of: advancedSettings) { newValue in
                guard !suppressSidebarSave else { return }
                persistSidebarSettings(newValue)
            }
            .onChange(of: isAdvancedMode) { newValue in
                if !newValue {
                    withAnimation(.easeInOut(duration: 0.2)) { macChatChrome.showAdvancedControls = false }
                }
            }
#endif
        }

#if os(macOS)
        private var macChatContainer: some View {
            HStack(spacing: 0) {
                macChatDrawer
                Divider()
                chatContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isAdvancedMode && macChatChrome.showAdvancedControls {
                    AdvancedSettingsSidebar(
                        settings: $advancedSettings,
                        model: modelManager.loadedModel,
                        models: modelManager.downloadedModels,
                        hide: { withAnimation(.easeInOut(duration: 0.2)) { macChatChrome.showAdvancedControls = false } }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }

        private var macChatDrawer: some View {
            ZStack(alignment: .topLeading) {
                AppTheme.sidebarBackground
                    .glassifyIfAvailable(in: Rectangle())
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Chats")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button(action: { vm.startNewSession() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("New Chat")
                        .guideHighlight(.chatNewChatButton)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    Divider()
                        .padding(.top, 4)

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(vm.sessions) { session in
                                drawerRow(for: session)
                                    .contentShape(Rectangle())
                                    .onTapGesture { vm.select(session) }
                                    .contextMenu {
                                        Button(session.isFavorite ? "Remove Favorite" : "Favorite") {
                                            vm.toggleFavorite(session)
                                        }
                                        Button(role: .destructive) {
                                            sessionToDelete = session
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: 280)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .guideHighlight(.chatSidebar)
            .confirmationDialog(
                "Delete chat \(sessionToDelete.map { drawerTitle(for: $0) } ?? "New chat")?",
                isPresented: Binding(
                    get: { sessionToDelete != nil },
                    set: { if !$0 { sessionToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        vm.delete(session)
                    }
                    sessionToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    sessionToDelete = nil
                }
            }
        }

        private struct HideMacListBackgroundIfAvailable: ViewModifier {
            func body(content: Content) -> some View {
                if #available(macOS 13, *) {
                    content.scrollContentBackground(.hidden)
                } else {
                    content
                }
            }
        }

        private func drawerRow(for session: ChatVM.Session) -> some View {
            let isSelected = session.id == vm.activeSessionID
            return VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(drawerTitle(for: session))
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if session.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.yellow)
                    }

                    Spacer(minLength: 0)
                }

                let preview = drawerPreview(for: session) ?? ""
                Text(preview.isEmpty ? " " : preview)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .secondary : .tertiary)
                    .lineLimit(1)
                    .opacity(preview.isEmpty ? 0 : 1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(isSelected ? 0.2 : 0), lineWidth: 1)
            )
        }

        private func drawerPreview(for session: ChatVM.Session) -> String? {
            func stripThinkBlocks(_ text: String) -> String {
                var result = text

                while let start = result.range(of: "<think>", options: .caseInsensitive) {
                    if let end = result.range(of: "</think>", options: .caseInsensitive, range: start.upperBound..<result.endIndex) {
                        result.removeSubrange(start.lowerBound..<end.upperBound)
                    } else {
                        result.removeSubrange(start.lowerBound..<result.endIndex)
                        break
                    }
                }

                return result.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
            }

            func condense(_ text: String) -> String? {
                let sanitized = stripThinkBlocks(text)
                let condensed = sanitized
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                guard !condensed.isEmpty else { return nil }

                if condensed.count > 80 {
                    let prefix = condensed.prefix(77)
                    return prefix + "…"
                }
                return condensed
            }

            var fallback: String?

            for message in session.messages.reversed() {
                let roleLowercased = message.role.lowercased()
                guard roleLowercased != "system" else { continue }
                if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

                let isAssistant = roleLowercased == "assistant" || message.role == "🤖"
                if isAssistant {
                    if let finalText = vm.finalAnswerText(for: message),
                       let condensed = condense(finalText) {
                        return condensed
                    }
                    continue
                }

                if fallback == nil {
                    fallback = condense(message.text)
                }
            }

            return fallback
        }

        private func drawerTitle(for session: ChatVM.Session) -> String {
            let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "New chat" : trimmed
        }

        private func syncSidebarSettings() {
            guard let model = modelManager.loadedModel else {
                suppressSidebarSave = true
                advancedSettings = ModelSettings()
                DispatchQueue.main.async { suppressSidebarSave = false }
                return
            }
            let latest = modelManager.settings(for: model)
            suppressSidebarSave = true
            advancedSettings = latest
            DispatchQueue.main.async { suppressSidebarSave = false }
        }

        private func persistSidebarSettings(_ settings: ModelSettings) {
            guard let model = modelManager.loadedModel else { return }
            modelManager.updateSettings(settings, for: model)
            vm.applyEnvironmentVariables(from: settings)
        }
#endif

        private var scrollBottomInset: CGFloat {
#if os(macOS)
            return 16
#else
            return 80
#endif
        }

        private var chatContent: some View {
            return VStack(spacing: 0) {
#if os(macOS)
                macChatToolbar
#endif
                if let ds = modelManager.activeDataset, vm.currentModelFormat != .slm {
                    // Modern dataset indicator pill
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.caption)
                            Text("Using \(ds.name)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue.gradient)
                        )
                        .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
#if os(macOS)
                        .onHover { hovering in
                            datasetPillHovered = hovering
                        }
                        .overlay(alignment: .trailing) {
                            if datasetPillHovered {
                                Button {
                                    vm.setDatasetForActiveSession(nil)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                                }
                                .buttonStyle(.plain)
                                .help("Stop using dataset")
                                .padding(.trailing, 6)
                            }
                        }
#endif
                        
                        Spacer()
                    }
                    .padding(.horizontal, UIConstants.defaultPadding)
                    .padding(.vertical, 8)
                    
                    // Show overlay only while deciding, or for full-content injection.
                    // Hide it for Smart Retrieval so the Chain-of-Thought think tags are visible immediately.
                    if vm.injectionStage == .deciding || (vm.injectionMethod == .full && vm.injectionStage != .none) {
                        HStack {
                            HStack(spacing: 8) {
                                if vm.injectionStage == .deciding {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                    Text("Analyzing context...")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                    let methodText = vm.injectionMethod == .full ? "Full Content" :
                                    vm.injectionMethod == .rag ? "Smart Retrieval" : "Processing"
                                    Text(methodText)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: vm.injectionStage == .deciding ?
                                        [Color.orange, Color.orange.opacity(0.8)] :
                                            [Color.green, Color.green.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                            )
                            .shadow(color: vm.injectionStage == .deciding ?
                                    Color.orange.opacity(0.3) : Color.green.opacity(0.3),
                                    radius: 4, x: 0, y: 2)
                            
                            Spacer()
                        }
                        .padding(.horizontal, UIConstants.defaultPadding)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.injectionStage)
                    }
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(vm.msgs.filter { $0.role != "system" }) { m in
                                MessageView(msg: m)
                                    .id(m.id)
                            }
                        }
                        .padding()
                        .padding(.bottom, scrollBottomInset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
#if canImport(UIKit) && !os(visionOS)
                    // On iOS/iPadOS, stop auto-scrolling when the user drags the list.
                    // Avoid attaching this drag gesture on macOS so text selection remains uninterrupted.
                    .simultaneousGesture(DragGesture().onChanged { _ in shouldAutoScrollToBottom = false })
#endif
                    // Centered suggestions overlay for brand-new empty chats
                    .overlay(alignment: .center) {
                        let isEmptyChat = vm.msgs.first(where: { $0.role != "system" }) == nil
                        if isEmptyChat && !vm.isStreaming && !vm.loading {
                            SuggestionsOverlay(
                                suggestions: suggestionTriplet,
                                enabled: vm.modelLoaded,
                                onTap: { text in
                                    guard vm.modelLoaded else { return }
                                    guard !vm.isStreamingInAnotherSession else {
                                        vm.crossSessionSendBlocked = true
                                        return
                                    }
                                    suggestionTriplet = []
                                    Task { await vm.sendMessage(text) }
                                },
                                onDisabledTap: {
                                    inputFocused = false
                                    showModelRequiredAlert = true
                                }
                            )
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !shouldAutoScrollToBottom && vm.isStreaming {
                            Button {
                                if let id = vm.msgs.last?.id {
                                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                                }
                                shouldAutoScrollToBottom = true
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.caption)
                                    .padding(10)
                                    .background(.thinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 96)
                        }
                    }
                    .onTapGesture {
                        inputFocused = false
                        hideKeyboard()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .thinkToggled)) { note in
                        guard let info = note.userInfo,
                              let idStr = info["messageId"] as? String,
                              let uuid = UUID(uuidString: idStr) else { return }
                        // Scroll to the message that had its think box closed
                        withAnimation {
                            proxy.scrollTo(uuid, anchor: .top)
                        }
                    }
                    .onChangeCompat(of: vm.msgs) { _, msgs in
                        if shouldAutoScrollToBottom, let id = msgs.last?.id {
                            // Use instant scroll during streaming for better performance,
                            // animated scroll only when not actively streaming
                            if vm.isStreaming {
                                proxy.scrollTo(id, anchor: .bottom)
                            } else {
                                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                            }
                        }
                        if let latest = msgs.last(where: { $0.role != "system" }) {
                            if latest.id != lastHapticMessageID {
                                lastHapticMessageID = latest.id
                                // Light feedback for bot replies, slightly stronger for user sends.
#if canImport(UIKit) && !os(visionOS)
                                let style: UIImpactFeedbackGenerator.FeedbackStyle = latest.role == "🤖" ? .light : .medium
                                Haptics.impact(style)
#else
                                Haptics.impact()
#endif
                            }
                        }
                    }
                    .onAppear {
                        // Pick suggestions when entering a new empty chat (only once)
                        let isEmpty = vm.msgs.first(where: { $0.role != "system" }) == nil
                        if isEmpty && suggestionTriplet.isEmpty {
                            suggestionTriplet = ChatSuggestions.nextThree()
                            suggestionsSessionID = vm.activeSessionID
                        }
                    }
                    .onChangeCompat(of: vm.activeSessionID) { _, newID in
                        // Rotate suggestions per new session if starting empty
                        let isEmpty = vm.msgs.first(where: { $0.role != "system" }) == nil
                        if isEmpty && newID != suggestionsSessionID {
                            suggestionTriplet = ChatSuggestions.nextThree()
                            suggestionsSessionID = newID
                        }
                    }
                    
                }
                let isIndexing = datasetManager.indexingDatasetID != nil
                ChatInputBox(text: $vm.prompt, focus: $inputFocused,
                             showModelRequiredAlert: $showModelRequiredAlert,
                             send: { let text = vm.prompt; vm.prompt = ""; Task { await vm.sendMessage(text) } },
                             stop: { vm.stop() },
                             canStop: vm.isStreaming)
                .guideHighlight(.chatInput)
                .opacity(vm.modelLoaded ? 1 : 0.6)
#if os(macOS)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 6)
#else
                .padding()
#endif
                if isIndexing {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text("Dataset indexing in progress...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("You can keep chatting while indexing finishes")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom)
                }
            }
            .alert("Load Failed", isPresented: Binding(get: { vm.loadError != nil }, set: { _ in vm.loadError = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.loadError ?? "")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }

#if os(macOS)
        private var macChatToolbar: some View {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    MacModelSelectorBar()
                        .frame(minWidth: 340, idealWidth: 400, maxWidth: 460)
                    Spacer()
                    Button { vm.startNewSession() } label: {
                        Image(systemName: "plus")
                    }
                    .padding(.vertical, 6)
                    .help("New Chat")
                    .buttonStyle(.plain)
                    .guideHighlight(.chatNewChatButton)
                }
                .padding(.horizontal, 20)
                .frame(height: 48)
                Divider()
            }
            .background(AppTheme.windowBackground.opacity(0.5))
            .glassifyIfAvailable(in: Rectangle())
            .macWindowDragDisabled()
            // Ensure toolbar sits visually above background visuals.
            .zIndex(2)
        }
#endif

        private var modelHeader: some View {
            Group {
                if let remote = modelManager.activeRemoteSession {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(remote.modelName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(remote.backendName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        remoteConnectionIndicator(for: remote)
                        Button(action: {
                            performMediumImpact()
                            vm.deactivateRemoteSession()
                        }) {
                            Image(systemName: "eject")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(6)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        Text(
                            showPercent
                                ? "\(Int(Double(vm.totalTokens) / vm.contextLimit * 100)) %"
                                : "\(vm.totalTokens) tok"
                        )
                        .font(.caption2)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                        .foregroundColor(.secondary)
                        .onTapGesture { showPercent.toggle() }
                    }
                } else if let loaded = modelManager.loadedModel {
                    HStack(spacing: 8) {
                        Text(loaded.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Button(action: {
                            performMediumImpact()
                            modelManager.loadedModel = nil
                            Task { await vm.unload() }
                        }) {
                            Image(systemName: "eject")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(6)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        Text(
                            showPercent
                                ? "\(Int(Double(vm.totalTokens) / vm.contextLimit * 100)) %"
                                : "\(vm.totalTokens) tok"
                        )
                        .font(.caption2)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                        .foregroundColor(.secondary)
                        .onTapGesture { showPercent.toggle() }
                    }
                } else {
                    let favourites = quickLoadFavourites
                    let recents = quickLoadRecents
                    Menu {
                        if favourites.isEmpty && recents.isEmpty {
                            Button(LocalizedStringKey("Open Model Library")) {
                                tabRouter.selection = .explore
                                UserDefaults.standard.set(ExploreSection.models.rawValue, forKey: "exploreSection")
                            }
                        } else {
                            if !favourites.isEmpty {
                                Section(LocalizedStringKey("Favorites")) {
                                    ForEach(favourites, id: \.id) { model in
                                        Button {
                                            quickLoadIfPossible(model)
                                        } label: {
                                            quickLoadLabel(for: model, isFavourite: true)
                                        }
                                    }
                                }
                            }
                            if !recents.isEmpty {
                                Section(LocalizedStringKey("Recent")) {
                                    ForEach(recents, id: \.id) { model in
                                        Button {
                                            quickLoadIfPossible(model)
                                        } label: {
                                            quickLoadLabel(for: model, isFavourite: false)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(LocalizedStringKey("No model >"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .menuIndicator(.hidden)
                    .disabled(vm.loading)
                }
            }
        }
        
        private func remoteConnectionBadge(for session: ActiveRemoteSession) -> some View {
            let color: Color
            switch session.transport {
            case .cloudRelay:
                color = .teal
            case .lan:
                color = .green
            case .direct:
                color = .blue
            }
            return HStack(spacing: 6) {
                Image(systemName: session.transport.symbolName)
                Text(session.transport.label)
                if session.streamingEnabled {
                    Image(systemName: "waveform")
                }
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundColor(color)
            .accessibilityLabel("Connection via \(session.transport.label)")
        }
        
        
        @ViewBuilder
        private func remoteConnectionIndicator(for session: ActiveRemoteSession) -> some View {
            if session.endpointType == .noemaRelay {
                let color: Color = {
                    switch session.transport {
                    case .cloudRelay: return .teal
                    case .lan: return .green
                    case .direct: return .blue
                    }
                }()
                HStack(spacing: 4) {
                    Image(systemName: session.transport.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                    if session.streamingEnabled {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .padding(6)
                .background(color.opacity(0.18), in: Capsule())
                .foregroundStyle(color)
                .accessibilityLabel("Connection via \(session.transport.label)")
            } else {
                remoteConnectionBadge(for: session)
            }
        }

        private var quickLoadFavourites: [LocalModel] {
            modelManager.favouriteModels(limit: modelManager.favouriteCapacity)
        }
        
        private var quickLoadRecents: [LocalModel] {
            let favouriteIDs = Set(quickLoadFavourites.map(\.id))
            return modelManager.recentModels(limit: 3, excludingIDs: favouriteIDs)
        }
        
        @ViewBuilder
        private func quickLoadLabel(for model: LocalModel, isFavourite: Bool) -> some View {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(quickLoadSubtitle(for: model))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: isFavourite ? "star.fill" : "clock")
                    .foregroundColor(isFavourite ? .yellow : .secondary)
            }
        }
        
        private func quickLoadSubtitle(for model: LocalModel) -> String {
            var parts: [String] = []
            if model.format != .slm && !model.quant.isEmpty {
                parts.append(model.quant)
            }
            parts.append(model.format.rawValue)
            return parts.joined(separator: " · ")
        }
        
        private func quickLoadIfPossible(_ model: LocalModel) {
            guard quickLoadInProgress == nil else { return }
            guard !vm.loading else { return }
            quickLoad(model)
        }
        
        private func quickLoad(_ model: LocalModel) {
            quickLoadInProgress = model.id
            Task { @MainActor in
                defer { quickLoadInProgress = nil }
                
                if model.format == .slm {
#if canImport(LeapSDK)
                    do {
                        LeapBundleDownloader.sanitizeBundleIfNeeded(at: model.url)
                        let runner = try await Leap.load(url: model.url)
                        vm.activate(runner: runner, url: model.url)
                        modelManager.updateSettings(ModelSettings.default(for: .slm), for: model)
                        modelManager.markModelUsed(model)
                        tabRouter.selection = .chat
                    } catch {
                        vm.loadError = error.localizedDescription
                        modelManager.loadedModel = nil
                    }
                    return
#else
                    vm.loadError = String(
                        localized: "SLM models are not supported on this platform.",
                        locale: LocalizationManager.preferredLocale()
                    )
                    modelManager.loadedModel = nil
                    return
#endif
                }
                
                await vm.unload()
                try? await Task.sleep(nanoseconds: 200_000_000)
                
                var settings = modelManager.settings(for: model)
                if model.format == .gguf && settings.gpuLayers == 0 {
                    settings.gpuLayers = -1
                }
                
                let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
                let ctx = Int(settings.contextLength)
                let layerHint: Int? = model.totalLayers > 0 ? model.totalLayers : nil
                if !ModelRAMAdvisor.fitsInRAM(format: model.format, sizeBytes: sizeBytes, contextLength: ctx, layerCount: layerHint, moeInfo: model.moeInfo) {
                    vm.loadError = String(
                        localized: "Model likely exceeds memory budget. Lower context or choose a smaller quant.",
                        locale: LocalizationManager.preferredLocale()
                    )
                    modelManager.loadedModel = nil
                    return
                }
                
                var loadURL = model.url
                switch model.format {
                case .gguf:
                    var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir) {
                            if isDir.boolValue {
                                if let f = InstalledModelsStore.firstGGUF(in: loadURL) {
                                    loadURL = f
                                } else {
                                    vm.loadError = String(
                                        localized: "Model file missing (.gguf)",
                                        locale: LocalizationManager.preferredLocale()
                                    )
                                    modelManager.loadedModel = nil
                                    return
                                }
                            } else if loadURL.pathExtension.lowercased() != "gguf" || !InstalledModelsStore.isValidGGUF(at: loadURL) {
                                if let f = InstalledModelsStore.firstGGUF(in: loadURL.deletingLastPathComponent()) {
                                    loadURL = f
                                } else {
                                    vm.loadError = String(
                                        localized: "Model file missing (.gguf)",
                                        locale: LocalizationManager.preferredLocale()
                                    )
                                    modelManager.loadedModel = nil
                                    return
                                }
                            }
                    } else {
                        if let alt = InstalledModelsStore.firstGGUF(in: InstalledModelsStore.baseDir(for: .gguf, modelID: model.modelID)) {
                            loadURL = alt
                        } else {
                            vm.loadError = String(
                                localized: "Model path missing",
                                locale: LocalizationManager.preferredLocale()
                            )
                            modelManager.loadedModel = nil
                            return
                        }
                    }
                case .mlx:
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir) {
                        loadURL = isDir.boolValue ? loadURL : loadURL.deletingLastPathComponent()
                    } else {
                        var d: ObjCBool = false
                        let dir = InstalledModelsStore.baseDir(for: .mlx, modelID: model.modelID)
                        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &d), d.boolValue {
                            loadURL = dir
                        } else {
                            vm.loadError = String(
                                localized: "Model path missing",
                                locale: LocalizationManager.preferredLocale()
                            )
                            modelManager.loadedModel = nil
                            return
                        }
                    }
                case .slm:
                    return
                case .apple:
                    vm.loadError = String(
                        localized: "Unsupported model format",
                        locale: LocalizationManager.preferredLocale()
                    )
                    modelManager.loadedModel = nil
                    return
                }
                
                var pendingFlagSet = false
                defer {
                    if pendingFlagSet {
                        UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
                    }
                }
                
                UserDefaults.standard.set(true, forKey: "bypassRAMLoadPending")
                pendingFlagSet = true
                
                let success = await vm.load(url: loadURL, settings: settings, format: model.format)
                if success {
                    modelManager.updateSettings(settings, for: model)
                    ModelSettingsStore.save(settings: settings, forModelID: model.modelID, quantLabel: model.quant)
                    modelManager.markModelUsed(model)
                    tabRouter.selection = .chat
                } else {
                    modelManager.loadedModel = nil
                }
            }
        }

#if os(macOS)
        private struct AdvancedSettingsSidebar: View {
            @Binding var settings: ModelSettings
            let model: LocalModel?
            let models: [LocalModel]
            let hide: () -> Void

            private var helperOptions: [LocalModel] {
                guard let base = model else { return [] }
                return models.filter { candidate in
                    guard candidate.id != base.id else { return false }
                    guard candidate.matchesArchitectureFamily(of: base) else { return false }
                    let baseSize = base.sizeGB
                    let candidateSize = candidate.sizeGB
                    if baseSize > 0, candidateSize > 0, candidateSize - baseSize > 0.01 {
                        return false
                    }
                    return true
                }
            }

            private var format: ModelFormat? { model?.format }

            private var supportsMinP: Bool { format == .gguf }
            private var supportsPresencePenalty: Bool { format == .gguf }
            private var supportsFrequencyPenalty: Bool { format == .gguf }
            private var supportsSpeculativeDecoding: Bool {
#if os(macOS)
                // Hide speculative decoding controls on macOS
                return false
#elseif os(visionOS)
                return false
#else
                return format == .gguf
#endif
            }

            var body: some View {
                VStack(spacing: 0) {
                    HStack {
                        Text("Advanced Controls")
                            .font(.headline)
                        Spacer()
                        Button(action: hide) {
                            Image(systemName: "sidebar.trailing")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.plain)
                        .help("Collapse controls")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            samplingSection
                            if supportsSpeculativeDecoding {
                                speculativeSection
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                }
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(alignment: .leading) {
                    Color.primary.opacity(0.08)
                        .frame(width: 1)
                        .ignoresSafeArea()
                }
            }

            private var samplingSection: some View {
                sidebarSection(title: "Sampling", systemImage: "dial.medium") {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            sliderRow("Temperature", value: $settings.temperature, range: 0...2, step: 0.05)
                            Text("Creativity: \(settings.temperature, format: .number.precision(.fractionLength(2))). Low values focus responses; high values add variety.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sliderRow("Top-p", value: $settings.topP, range: 0...1, step: 0.01)
                            Text("Top-p: \(settings.topP, format: .number.precision(.fractionLength(2)))")
                                .font(.footnote.monospacedDigit())
                        }

                        Stepper(value: $settings.topK, in: 1...2048, step: 1) {
                            Text("Top-k: \(settings.topK)")
                        }

                        if supportsMinP {
                            VStack(alignment: .leading, spacing: 8) {
                                sliderRow("Min-p", value: $settings.minP, range: 0...1, step: 0.01)
                                Text("Min-p: \(settings.minP, format: .number.precision(.fractionLength(2)))")
                                    .font(.footnote.monospacedDigit())
                            }
                        }

                        Stepper(
                            value: Binding(
                                get: { Double(settings.repetitionPenalty) },
                                set: { settings.repetitionPenalty = Float($0) }
                            ),
                            in: 0.8...2.0,
                            step: 0.05
                        ) {
                            Text("Repetition penalty: \(Double(settings.repetitionPenalty), format: .number.precision(.fractionLength(2)))")
                        }

                        Stepper(value: $settings.repeatLastN, in: 0...4096, step: 16) {
                            Text("Repeat last N tokens: \(settings.repeatLastN)")
                        }

                        if supportsPresencePenalty {
                            Stepper(
                                value: Binding(
                                    get: { Double(settings.presencePenalty) },
                                    set: { settings.presencePenalty = Float($0) }
                                ),
                                in: -2.0...2.0,
                                step: 0.1
                            ) {
                                Text("Presence penalty: \(Double(settings.presencePenalty), format: .number.precision(.fractionLength(1)))")
                            }
                        }

                        if supportsFrequencyPenalty {
                            Stepper(
                                value: Binding(
                                    get: { Double(settings.frequencyPenalty) },
                                    set: { settings.frequencyPenalty = Float($0) }
                                ),
                                in: -2.0...2.0,
                                step: 0.1
                            ) {
                                Text("Frequency penalty: \(Double(settings.frequencyPenalty), format: .number.precision(.fractionLength(1)))")
                            }
                        }

                        Text("Smooth loops and phrase echo by balancing repetition controls.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model == nil)
            }

            private var speculativeSection: some View {
                sidebarSection(title: "Speculative Decoding", systemImage: "bolt.fill") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Speed up with a smaller helper model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Helper Model", selection: Binding(
                            get: { settings.speculativeDecoding.helperModelID },
                            set: { settings.speculativeDecoding.helperModelID = $0 }
                        )) {
                            Text("None").tag(String?.none)
                            ForEach(helperOptions, id: \.id) { candidate in
                                Text(candidate.name).tag(String?.some(candidate.id))
                            }
                        }

                        if helperOptions.isEmpty {
                            Text("Install another model with the same architecture and equal or smaller size to enable speculative decoding.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if settings.speculativeDecoding.helperModelID != nil {
                            Picker("Draft strategy", selection: $settings.speculativeDecoding.mode) {
                                ForEach(ModelSettings.SpeculativeDecodingSettings.Mode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            Stepper(value: $settings.speculativeDecoding.value, in: 1...2048, step: 1) {
                                switch settings.speculativeDecoding.mode {
                                case .tokens:
                                    Text("Draft tokens: \(settings.speculativeDecoding.value)")
                                case .max:
                                    Text("Draft window: \(settings.speculativeDecoding.value)")
                                }
                            }
                        }
                    }
                }
            }


            private func sidebarSection<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
                VStack(alignment: .leading, spacing: 16) {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                    content()
                }
            }

            private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                    Slider(value: value, in: range, step: step)
                        .padding(.vertical, 2)
                }
            }
        }
#endif

        private var sidebar: some View {
            return VStack(alignment: .leading) {
                HStack {
                    Text("Recent Chats").font(.headline)
                    Spacer()
                    Button(action: { vm.startNewSession() }) { Image(systemName: "plus") }
                }
                .padding()
                List(selection: $vm.activeSessionID) {
                    ForEach(vm.sessions) { session in
                        HStack {
                            Image(systemName: session.isFavorite ? "star.fill" : "message")
                            Text(session.title)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            vm.select(session)
                            withAnimation { showSidebar = false }
                        }
                        .contextMenu {
                            Button(session.isFavorite ? "Unfavorite" : "Favorite") { vm.toggleFavorite(session) }
                            Button(role: .destructive) { sessionToDelete = session } label: { Text("Delete") }
                        }
                        .swipeActions {
                            Button(role: .destructive) { sessionToDelete = session } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
                .confirmationDialog("Delete chat \(sessionToDelete?.title ?? "")?", isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } })) {
                    Button("Delete", role: .destructive) { if let s = sessionToDelete { vm.delete(s); sessionToDelete = nil } }
                    Button("Cancel", role: .cancel) { sessionToDelete = nil }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .ignoresSafeArea(edges: .bottom)
        }
        
        
    }
    
    // MARK: - Citation UI
    private struct SuggestionsOverlay: View {
        let suggestions: [String]
        let enabled: Bool
        let onTap: (String) -> Void
        let onDisabledTap: () -> Void
        
        var body: some View {
            VStack(spacing: 20) {
                Image("Noema")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .opacity(0.9)
                    .accessibilityHidden(true)
                
                VStack(spacing: 12) {
                    ForEach(suggestions.prefix(3), id: \.self) { s in
                        Button(action: {
                            if enabled {
                                onTap(s)
                            } else {
                                onDisabledTap()
                            }
                        }) {
                            Text(s)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: 520)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .padding(.horizontal)
                        .opacity(enabled ? 1.0 : 0.6)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }
    
    private struct CitationButton: View {
        let index: Int
        let text: String
        let source: String?
        @State private var show = false
        
        var body: some View {
            Button(action: { show = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "book")
                        .font(.caption)
                    Text("\(index)")
                        .font(.caption2).bold()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $show) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Citation \(index)").font(.headline)
                            if let source = source {
                                Text("Source: \(source)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("Close") { show = false }
                    }
                    ScrollView {
                        MathRichText(source: text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding()
                .frame(minWidth: 300, minHeight: 200)
            }
        }
    }

    // URLSession downloadWithProgress moved to URLSession+DownloadWithProgress.swift
    
    // Helper functions for global indexing overlay
    private func globalStageColor(_ stage: DatasetProcessingStage, current: DatasetProcessingStage) -> Color {
        switch (stage, current) {
        case (.extracting, .extracting), (.compressing, .compressing), (.embedding, .embedding):
            return .blue
        case (.extracting, .compressing), (.extracting, .embedding), (.compressing, .embedding):
            return .green
        default:
            return .gray.opacity(0.3)
        }
    }
    
    private func globalStageLabel(_ stage: DatasetProcessingStage) -> String {
        switch stage {
        case .extracting: return "Extracting"
        case .compressing: return "Compressing"
        case .embedding: return "Embedding"
        case .completed: return "Ready"
        case .failed: return "Failed"
        }
    }
    
}

#endif
