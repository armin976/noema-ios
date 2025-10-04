// ExploreView.swift
import SwiftUI
#if canImport(LeapSDK)
import LeapSDK
#endif

/// Simple badge label style used to display small status indicators.
struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
        } icon: {
            configuration.icon
        }
        .padding(4)
        .background(
            Capsule().fill(Color(.systemGray5))
        )
    }
}

extension LabelStyle where Self == BadgeLabelStyle {
    static var badge: BadgeLabelStyle { .init() }
}

struct ExploreView: View {
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var chatVM: ChatVM
    @EnvironmentObject var tabRouter: TabRouter
    @EnvironmentObject var downloadController: DownloadController
    @EnvironmentObject var filterManager: ModelTypeFilterManager
    @EnvironmentObject var walkthrough: GuidedWalkthroughManager
    @AppStorage("huggingFaceToken") private var huggingFaceToken = ""
    @StateObject private var vm: ExploreViewModel

    init() {
        let token = UserDefaults.standard.string(forKey: "huggingFaceToken") ?? ""
        _vm = StateObject(wrappedValue: ExploreViewModel(
            registry: CombinedRegistry(primary: HuggingFaceRegistry(token: token),
                                       extras: [ManualModelRegistry()])))
    }
    @State private var selected: ModelDetails?
    @State private var loadingDetail = false
    @State private var openingModelId: String?

    var body: some View { contentView }

    @ViewBuilder
    private var contentView: some View {
        listView
            .onChange(of: huggingFaceToken) { _, newValue in
                updateRegistry(newValue)
            }
            .onChange(of: filterManager.filter) { _, _ in
                // Trigger a new search when filter changes
                if !vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    vm.triggerSearch()
                }
            }
            .task { 
                await vm.loadCurated()
                vm.setFilterManager(filterManager)
            }
            // Title provided by parent container
            .toolbar { searchModeToolbar }
            .sheet(item: $selected, content: detailSheet)
            .overlay { if loadingDetail { ProgressView() } }
            .overlay { if vm.isLoadingSearch { ProgressView() } }
            .overlay { searchEmptyOverlay }
            .onChange(of: downloadController.navigateToDetail) { _, newValue in
                handleNavigation(newValue)
            }
            .alert("Error", isPresented: hasSearchError) {
                Button("OK", role: .cancel) { vm.searchError = nil }
            } message: {
                Text(vm.searchError ?? "")
            }
            .onReceive(walkthrough.$step) { step in
                switch step {
                case .exploreModelTypes:
                    if vm.searchMode != .gguf {
                        vm.searchMode = .gguf
                        vm.triggerSearch()
                    }
                case .exploreMLX:
                    if DeviceGPUInfo.supportsGPUOffload && vm.searchMode != .mlx {
                        vm.searchMode = .mlx
                        vm.triggerSearch()
                    }
                case .exploreSLM:
                    if vm.searchMode != .slm {
                        vm.searchMode = .slm
                        vm.triggerSearch()
                    }
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var listView: some View {
        if vm.searchMode == .slm {
            List { listContent }
        } else {
            List { listContent }
                .searchable(text: $vm.searchText)
                .onSubmit(of: .search) { vm.triggerSearch() }
        }
    }

    private func updateRegistry(_ token: String) {
        vm.updateRegistry(CombinedRegistry(primary: HuggingFaceRegistry(token: token),
                                           extras: [ManualModelRegistry()]))
    }

    private func handleNavigation(_ detail: ModelDetails?) {
        if let d = detail {
            selected = d
            downloadController.navigateToDetail = nil
        }
    }

    private var hasSearchError: Binding<Bool> {
        Binding(get: { vm.searchError != nil }, set: { if !$0 { vm.searchError = nil } })
    }

    @ViewBuilder
    private func detailSheet(_ detail: ModelDetails) -> some View {
        ExploreDetailView(detail: detail)
            .environmentObject(modelManager)
            .environmentObject(chatVM)
            .environmentObject(downloadController)
    }

    @ViewBuilder
    private var searchEmptyOverlay: some View {
        if vm.isSearching && !vm.isLoadingSearch && vm.searchResults.isEmpty {
            VStack(spacing: 8) {
                Text("No models found for '\(vm.searchText)'")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(
                    DeviceGPUInfo.supportsGPUOffload
                    ? "Try:\n• Different keywords (e.g., 'gemma-3' instead of 'gemma 3')\n• Switching between GGUF/MLX modes\n• Adjusting the text/vision filter\n• Checking your search filters"
                    : "Try:\n• Different keywords (e.g., 'gemma-3' instead of 'gemma 3')\n• Switching between GGUF/SLM modes\n• Adjusting the text/vision filter\n• Checking your search filters"
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var listContent: some View {
#if canImport(LeapSDK)
        if vm.searchMode == .slm {
            Section("SLM Models - Liquid AI") {
                ForEach(vm.filteredLeap) { entry in
                    LeapRowView(entry: entry, openAction: { e, url, runner in
                        openLeap(entry: e, url: url, runner: runner)
                    })
                        .environmentObject(downloadController)
                }
            }
        } else {
            standardSections
        }
#else
        standardSections
#endif
    }

    @ViewBuilder
    private var standardSections: some View {
        if vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            Section("Recommended") {
                ForEach(filteredRecommended, id: \._stableKey, content: recordButton)
            }
        } else {
            Section("Results") {
                ForEach(filteredSearchResults, id: \._stableKey, content: recordButton)
                if vm.canLoadMore {
                    ProgressView().onAppear { vm.loadNextPage() }
                }
            }
        }
    }
    
    // MARK: - Filtered Results
    
    private var filteredRecommended: [ModelRecord] {
        var seen = Set<String>()
        return vm.recommended.filter { rec in
            filterManager.shouldIncludeModel(rec) && seen.insert(rec.id).inserted
        }
    }
    
    private var filteredSearchResults: [ModelRecord] {
        var seen = Set<String>()
        return vm.searchResults.filter { rec in
            filterManager.shouldIncludeModel(rec) && seen.insert(rec.id).inserted
        }
    }

    @ViewBuilder
    private func recordButton(_ record: ModelRecord) -> some View {
        Button { Task { await open(record) } } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(record.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    // Vision badge (non-blocking) — hidden while multimodal UI is disabled
                    if UIConstants.showMultimodalUI {
                        VisionBadge(repoId: record.id, pipelineTag: record.pipeline_tag, searchTags: record.tags, token: huggingFaceToken)
                    }
                    // Tool capability badge (non-blocking)
                    ToolBadge(repoId: record.id, token: huggingFaceToken)
                    if record.isReasoningModel {
                        Image(systemName: "brain")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
                if !record.publisher.isEmpty {
                    Text(authorListText(for: record))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                if !record.hasInstallableQuant {
                    Text("No quant files available")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func authorListText(for record: ModelRecord) -> String {
        // Currently HF search returns a single owner (publisher). We surface it, and if we
        // later enrich with more authors from metadata, join them here.
        return record.publisher
    }

    @ToolbarContentBuilder
    private var searchModeToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { vm.toggleMode() }) {
                Text(vm.searchMode.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(searchModeGradient)
                    .clipShape(Capsule())
                    .foregroundColor(.white)
            }
            .guideHighlight(.exploreModelToggle)
        }
    }

    private var searchModeGradient: LinearGradient {
        switch vm.searchMode {
        case .gguf:
            return ModelFormat.gguf.tagGradient
        case .mlx:
            return ModelFormat.mlx.tagGradient
        case .slm:
            return ModelFormat.slm.tagGradient
        }
    }

    @MainActor
    private func open(_ record: ModelRecord) async {
        if openingModelId == record.id { return }
        openingModelId = record.id
        defer { openingModelId = nil }
        // Log pipeline tag and tags from the search record when the model is tapped
        print("[ExploreView] Model tapped: \(record.id) pipeline_tag: \(record.pipeline_tag ?? "nil") tags: \(record.tags ?? [])")
        if let pipeline = record.pipeline_tag?.lowercased(), pipeline == "image-text-to-text" {
            print("[ExploreView] 🎯 Vision detected via pipeline tag for model \(record.id)")
        }

        // Avoid prefetching HF metadata here to reduce unnecessary calls
        // We'll fetch details and metadata only when needed in the detail view

        loadingDetail = true
        if let d = await vm.details(for: record.id) {
            selected = d
        }
        loadingDetail = false
    }

#if canImport(LeapSDK)
    @MainActor
    private func openLeap(entry: LeapCatalogEntry, url: URL, runner: ModelRunner) {
        chatVM.activate(runner: runner, url: url)
        let local = modelManager.downloadedModels.first(where: { $0.modelID == entry.slug }) ??
            LocalModel(
                modelID: entry.slug,
                name: entry.displayName,
                url: url,
                quant: "",
                architecture: entry.slug,
                format: .slm,
                sizeGB: Double(entry.sizeBytes) / 1_073_741_824.0,
                isMultimodal: false,
                isToolCapable: false,
                isDownloaded: true,
                downloadDate: Date(),
                lastUsedDate: nil,
                isFavourite: false,
                totalLayers: 0
            )
        modelManager.updateSettings(ModelSettings.default(for: .slm), for: local)
        modelManager.markModelUsed(local)
        tabRouter.selection = .chat
    }
#endif
}

private struct VisionBadge: View {
    let repoId: String
    let pipelineTag: String?
    let searchTags: [String]?
    let token: String
    @State private var isVision = false
    @EnvironmentObject var filterManager: ModelTypeFilterManager
    
    var body: some View {
        Group {
            if isVision {
                // Compact yellow eye icon (rounded square with stroke) to indicate vision-capable models
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    Image(systemName: "eye.fill")
                        .foregroundColor(Color.yellow)
                        .font(.system(size: 11, weight: .semibold))
                }
                .help("Vision-capable model")
            }
        }
        .onAppear {
            // Use the same immediate detection logic as the filter manager
            checkVisionCapability()
        }
        .task {
            // Re-check when component appears to ensure immediate display
            checkVisionCapability()
        }
        .task(id: repoId) {
            // Avoid HF API calls for badges; use cached/heuristic only
            if !isVision {
                isVision = VisionModelDetector.isVisionModelCachedOrHeuristic(repoId: repoId)
            }
        }
        .onChange(of: filterManager.filter) { _, _ in
            // Re-check when filter changes to ensure badge shows
            checkVisionCapability()
        }
        .onChange(of: pipelineTag) { _, _ in
            // Respond if pipeline tag becomes available later
            checkVisionCapability()
        }
        .onChange(of: searchTags) { _, _ in
            // Respond if tags become available later
            checkVisionCapability()
        }
        .task {
            await checkVisionCapabilityAsync()
        }
    }
    
    private func checkVisionCapability() {
        #if DEBUG
        print("[VisionBadge] Checking vision capability for \(repoId)")
        print("[VisionBadge] pipeline_tag: \(pipelineTag ?? "nil")")
        print("[VisionBadge] tags: \(searchTags ?? [])")
        #endif
        
        // Check pipeline_tag first (same logic as filter manager)
        if let pipelineTag = pipelineTag?.lowercased(),
           pipelineTag == "image-text-to-text" {
            print("[VisionBadge] ✅ Vision detected via pipeline_tag for \(repoId): \(pipelineTag)")
            isVision = true
            return
        }
        
        // Check tags (same logic as filter manager)
        if let tags = searchTags?.map({ $0.lowercased() }),
           tags.contains("image-text-to-text") {
            print("[VisionBadge] ✅ Vision detected via tags for \(repoId): \(tags)")
            isVision = true
            return
        }
        
        print("[VisionBadge] ❌ No vision capability detected for \(repoId)")
    }
    
    private func checkVisionCapabilityAsync() async {
        // Only do async checks if immediate detection didn't work
        if isVision { return }
        
        print("[VisionBadge] 🔄 Trying async detection for \(repoId)")
        
        // Try cached metadata; only trust pipeline tag
        if let meta = HuggingFaceMetadataCache.cached(repoId: repoId) {
            await MainActor.run { isVision = meta.isVision }
            if isVision {
                print("[VisionBadge] ✅ Vision detected via cached metadata for \(repoId) pipeline: \(meta.pipelineTag ?? "nil") tags: \(meta.tags ?? [])")
                return
            }
        }
        
        // Avoid fresh HF fetches for badges; rely on cached metadata only
        // This prevents unnecessary API calls while browsing the list
        
        print("[VisionBadge] ❌ No vision capability detected via async methods for \(repoId)")
    }
}

private struct ToolBadge: View {
    let repoId: String
    let token: String
    @State private var isToolCapable = false
    
    var body: some View {
        Group {
            if isToolCapable {
                HStack(spacing: 2) {
                    Image(systemName: "wrench.fill")
                        .font(.caption2)
                    Text("Tools")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                )
            }
        }
        .task(id: repoId) {
            isToolCapable = await ToolCapabilityDetector.isToolCapable(repoId: repoId, token: token)
        }
    }
}

private extension ModelRecord {
    // Stable view key to avoid duplicate ID warnings when records collide in the same section
    var _stableKey: String {
        let fmtHash = formats.hashValue
        let tag = (pipeline_tag ?? "").hashValue
        return "\(id)|\(fmtHash)|\(tag)"
    }
}

struct ExploreDetailView: View, Identifiable {
    let id = UUID()
    let detail: ModelDetails
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var chatVM: ChatVM
    @EnvironmentObject var tabRouter: TabRouter
    @EnvironmentObject var downloadController: DownloadController
    @Environment(\.dismiss) private var dismiss
    @State private var progressMap: [String: Double] = [:]
    @State private var speedMap: [String: Double] = [:]
    @State private var downloading: Set<String> = []
    @StateObject private var readmeLoader: ModelReadmeLoader
    @State private var hubMeta: ModelHubMeta?
    @AppStorage("huggingFaceToken") private var huggingFaceToken = ""

    init(detail: ModelDetails) {
        self.detail = detail
        let token = UserDefaults.standard.string(forKey: "huggingFaceToken") ?? ""
        _readmeLoader = StateObject(wrappedValue: ModelReadmeLoader(repo: detail.id, token: token))
    }

    var body: some View {
        NavigationStack {
            List {
                // Add a header section with the model title
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text((detail.id.split(separator: "/").last).map(String.init) ?? detail.id)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if detail.id.contains("/") {
                            Text((detail.id.split(separator: "/").first).map(String.init) ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowBackground(Color.clear)
                
                Section(header:
                            HStack {
                                Text("Model Details")
                                Spacer()
                                if UIConstants.showMultimodalUI, let meta = hubMeta, meta.isVision {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.yellow, lineWidth: 2)
                                            .frame(width: 22, height: 22)
                                        Image(systemName: "eye.fill")
                                            .foregroundColor(Color.yellow)
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .help("Vision-capable model")
                                }
                            }
                ) {
                    ReadmeCollapseView(markdown: readmeLoader.markdown,
                                      loading: readmeLoader.isLoading,
                                      retry: { readmeLoader.load(force: true) })
                        .onAppear {
                            readmeLoader.load()
                            // Populate hubMeta using cached value first, then refresh
                            Task {
                                if let cached = HuggingFaceMetadataCache.cached(repoId: detail.id) {
                                    hubMeta = cached
                                }
                                // Avoid background refresh to reduce HF calls; user can refresh README manually
                                // if let fresh = await HuggingFaceMetadataCache.fetchAndCache(repoId: detail.id, token: UserDefaults.standard.string(forKey: "huggingFaceToken")) {
                                //     hubMeta = fresh
                                // }
                            }
                        }
                        .onDisappear {
                            readmeLoader.clearMarkdown()
                            readmeLoader.cancel()
                        }
                }
                Section(header: Text("Quants")) {
                    if eligibleQuants.isEmpty {
                        Text("No ≥Q3 quants are available for this model.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(eligibleQuants) { q in
                            QuantRow(
                                canonicalID: detail.id,
                                info: q,
                                progress: Binding(
                                    get: {
                                        if let item = downloadController.items.first(where: { $0.detail.id == detail.id && $0.quant.label == q.label }) {
                                            return item.progress
                                        }
                                        return progressMap[q.label, default: 0]
                                    },
                                    set: { _ in }
                                ),
                                speed: Binding(
                                    get: {
                                        if let item = downloadController.items.first(where: { $0.detail.id == detail.id && $0.quant.label == q.label }) {
                                            return item.speed
                                        }
                                        return speedMap[q.label, default: 0]
                                    },
                                    set: { _ in }
                                ),
                                downloading: downloading.contains(q.label),
                                openAction: { await useModel(info: q) },
                                downloadAction: { await download(info: q) },
                                cancelAction: { cancelDownload(label: q.label) }
                            )
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear {
                if downloadController.items.contains(where: { $0.detail.id == detail.id }) {
                    downloadController.showOverlay = false
                }
            }
            .onDisappear {
                if !downloadController.items.isEmpty {
                    downloadController.showOverlay = true
                }
            }
            .onReceive(downloadController.$items) { items in
                for item in items where item.detail.id == detail.id {
                    progressMap[item.quant.label] = item.progress
                    speedMap[item.quant.label] = item.speed
                    if item.completed {
                        downloading.remove(item.quant.label)
                    } else if item.error != nil && !item.error!.isRetryable {
                        // Remove permanently failed downloads from downloading state
                        downloading.remove(item.quant.label)
                    }
                }
            }
        }
    }

    private var eligibleQuants: [QuantInfo] {
        detail.quants.filter { $0.isHighBitQuant }
    }

    private func fileURL(for info: QuantInfo) -> URL {
        var dir = InstalledModelsStore.baseDir(for: info.format, modelID: detail.id)
        dir.appendPathComponent(info.downloadURL.lastPathComponent)
        return dir
    }

    @MainActor
    private func download(info: QuantInfo) async {
        downloading.insert(info.label)
        progressMap[info.label] = 0
        speedMap[info.label] = 0
        downloadController.start(detail: detail, quant: info)
    }

    private func cancelDownload(label: String) {
        let id = "\(detail.id)-\(label)"
        downloadController.cancel(itemID: id)
        downloading.remove(label)
    }

    @MainActor
    private func useModel(info: QuantInfo) async {
        let url = fileURL(for: info)
        let name = url.deletingPathExtension().lastPathComponent
        
        // Detect vision and tool capabilities - prefer pipeline/tags first
        let token = huggingFaceToken
        
        // Prefer cached Hub pipeline tag; avoid fresh fetch here to reduce calls
        let meta = HuggingFaceMetadataCache.cached(repoId: detail.id)
        var isVision = meta?.isVision ?? false

        // Log pipeline tag and tags from the hub metadata when opening a quant
        if let pipeline = meta?.pipelineTag {
            print("[ExploreView] Quant opened: \(detail.id) pipeline_tag: \(pipeline) tags: \(meta?.tags ?? [])")
            if pipeline.lowercased() == "image-text-to-text" {
                print("[ExploreView] 🎯 Vision detected via pipeline tag for quant of model \(detail.id)")
            }
        } else {
            print("[ExploreView] Quant opened: \(detail.id) pipeline_tag: nil tags: \(meta?.tags ?? [])")
        }

        if !isVision {
            switch info.format {
            case .gguf:
                isVision = ChatVM.guessLlamaVisionModel(from: url)
            case .mlx:
                isVision = MLXBridge.isVLMModel(at: url)
            case .slm:
                let slug = detail.id.isEmpty ? url.deletingPathExtension().lastPathComponent : detail.id
                isVision = LeapCatalogService.isVisionQuantizationSlug(slug)
            case .apple:
                isVision = false
            }
        }
        // For capabilities on open, check hub/template hints with a single call; fallback to local scan
        var isToolCapable = await ToolCapabilityDetector.isToolCapable(repoId: detail.id, token: token)
        if isToolCapable == false {
            isToolCapable = ToolCapabilityDetector.isToolCapableLocal(url: url, format: info.format)
        }
        
        let local = LocalModel(
            modelID: detail.id,
            name: name,
            url: url,
            quant: info.label,
            architecture: detail.id,
            format: info.format,
            sizeGB: Double(info.sizeBytes) / 1_073_741_824.0,
            isMultimodal: isVision,
            isToolCapable: isToolCapable,
            isDownloaded: true,
            downloadDate: Date(),
            lastUsedDate: nil,
            isFavourite: false,
            totalLayers: ModelScanner.layerCount(for: url, format: info.format)
        )
        let settings = modelManager.settings(for: local)
        await chatVM.unload()
        if await chatVM.load(url: url, settings: settings, format: info.format) {
            // Persist effective settings for last used
            modelManager.updateSettings(settings, for: local)
            modelManager.markModelUsed(local)
            // Persist capabilities immediately so badges and image button show correctly
            modelManager.setCapabilities(modelID: detail.id, quant: info.label, isMultimodal: isVision, isToolCapable: isToolCapable)
        } else {
            modelManager.loadedModel = nil
        }
        tabRouter.selection = .stored
        dismiss()
    }
}

struct QuantRow: View {
    let canonicalID: String
    let info: QuantInfo
    @Binding var progress: Double
    @Binding var speed: Double
    let downloading: Bool
    let openAction: () async -> Void
    let downloadAction: () async -> Void
    let cancelAction: () -> Void
    @EnvironmentObject var downloadController: DownloadController
    @EnvironmentObject var modelManager: AppModelManager

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(info.label)
                    Text(info.format.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(info.format.tagGradient)
                        .clipShape(Capsule())
                        .foregroundColor(.white)
                }
                Text(sizeText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            suitabilityBadge
            trailingControls
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var suitabilityBadge: some View {
        // Use a reasonable default context for discovery views where per-model settings are not yet bound.
        let defaultCtx = 4096
        // We do not know the layer count at listing time; pass nil to use heuristic.
        ModelRAMAdvisor.badge(format: info.format, sizeBytes: info.sizeBytes, contextLength: defaultCtx, layerCount: nil)
    }

    @ViewBuilder
    private var trailingControls: some View {
        if downloading {
            VStack(spacing: 8) {
                let itemID = "\(canonicalID)-\(info.label)"
                let downloadItem = downloadController.items.first { $0.id == itemID }
                
                if let error = downloadItem?.error {
                    // Show error state
                    VStack {
                        Text(error.localizedDescription)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 120)
                    .padding(.leading, 4)
                } else {
                    // Show normal progress
                    ModernDownloadProgressView(progress: progress, speed: speed)
                        .frame(width: 120) // Keep a compact width so it doesn't collide with the quant label
                        .padding(.leading, 4)
                }
                HStack {
                    Spacer()
                    let itemID = "\(canonicalID)-\(info.label)"
                    let downloadItem = downloadController.items.first { $0.id == itemID }
                    
                    if let error = downloadItem?.error, error.isRetryable {
                        // Show retry button for network errors
                        Button(action: { downloadController.resume(itemID: itemID) }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Retry download")
                    } else if downloadController.paused.contains(itemID) {
                        // Show resume button for intentionally paused downloads
                        Button(action: { downloadController.resume(itemID: itemID) }) {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                    } else if downloadItem?.error == nil {
                        // Show pause button for active downloads
                        Button(action: { downloadController.pause(itemID: itemID) }) {
                            Image(systemName: "pause.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    Button(action: cancelAction) {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } else if isDownloaded {
            VStack {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .labelStyle(.badge)
                    .foregroundColor(.green)
                Button("Open") { Task { await openAction() } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Button("Download") { Task { await downloadAction() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private var isDownloaded: Bool {
        modelManager.downloadedModels.contains { $0.modelID == canonicalID && $0.quant == info.label }
    }

    private var sizeText: String {
        let mb = Double(info.sizeBytes) / 1_048_576.0
        if mb > 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    private var speedText: String {
        guard speed > 0 else { return "--" }
        let kb = speed / 1024
        if kb > 1024 { return String(format: "%.1f MB/s", kb / 1024) }
        return String(format: "%.0f KB/s", kb)
    }

}

struct ReadmeCollapseView: View {
    let markdown: String?
    let loading: Bool
    let retry: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading) {
            if let md = markdown {
                if expanded {
                    Text((try? AttributedString(markdown: md, options: .init(interpretedSyntax: .full))) ?? AttributedString(md))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text((try? AttributedString(markdown: preview(from: md), options: .init(interpretedSyntax: .full))) ?? AttributedString(preview(from: md)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            LinearGradient(colors: [.clear, Color(.systemBackground)],
                                           startPoint: .center, endPoint: .bottom)
                                .allowsHitTesting(false)
                        )
                }
            } else if loading {
                ProgressView()
            } else {
                Button("Retry") { retry() }
            }
        }
        .onTapGesture { withAnimation { expanded.toggle() } }
    }

    private func preview(from md: String) -> String {
        let lines = md.split(separator: "\n")
        return lines.prefix(3).joined(separator: "\n")
    }
}

#if canImport(LeapSDK)
struct LeapRowView: View {
    let entry: LeapCatalogEntry
    let openAction: (LeapCatalogEntry, URL, ModelRunner) -> Void
    @EnvironmentObject var downloadController: DownloadController
    @State private var state: LeapBundleDownloader.State = .notInstalled
    @State private var progress = 0.0
    @State private var speed = 0.0
    @State private var expectedBytes: Int64 = 0
    private let downloader = LeapBundleDownloader.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.displayName)
                Text(subtitleText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ModelRAMAdvisor.badge(format: .slm, sizeBytes: entry.sizeBytes, contextLength: 4096, layerCount: nil)
            actionButton
        }
        .onAppear { refresh() }
        .onReceive(downloadController.$leapItems) { _ in
            if let item = downloadController.leapItems.first(where: { $0.id == entry.slug }) {
                progress = item.progress
                speed = item.speed
                if item.expectedBytes > 0 { expectedBytes = item.expectedBytes }
                state = .downloading(progress)
            } else {
                refresh()
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .notInstalled:
            Button("Download") { start() }
                .buttonStyle(.borderedProminent)
        case .failed(let msg):
            Button(msg == "Paused" ? "Resume" : "Download") { start() }
                .buttonStyle(.borderedProminent)
        case .downloading(let p):
            HStack {
                // Prefer the progress reported in state (from downloader.statusAsync),
                // fall back to local progress state which is kept in sync via DownloadController.
                let current = p > 0 ? p : progress
                ProgressView(value: current)
                    .frame(width: 80)
                    .modernProgress()
                Group { Text(speedText(speed)) }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button(action: { downloadController.cancel(itemID: entry.slug) }) {
                    Image(systemName: "stop.fill")
                }.buttonStyle(.borderless)
            }
        case .installed:
            Button("Load") { load() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func refresh() {
        Task { @MainActor in
            state = await downloader.statusAsync(for: entry)
            if case .downloading(let p) = state { progress = p }
        }
    }

    private var sizeText: String {
        let bytes = expectedBytes > 0 ? expectedBytes : entry.sizeBytes
        if bytes <= 0 { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var subtitleText: String {
        let size = sizeText
        if size.isEmpty { return entry.slug }
        return "\(entry.slug) \u{2022} \(size)"
    }

    private func speedText(_ speed: Double) -> String {
        guard speed > 0 else { return "--" }
        let kb = speed / 1024
        if kb > 1024 { return String(format: "%.1f MB/s", kb / 1024) }
        return String(format: "%.0f KB/s", kb)
    }

    private func start() {
        downloadController.startLeap(entry: entry)
    }

    private func load() {
        guard case .installed(let url) = state else { return }
        Task { @MainActor in
            do {
                LeapBundleDownloader.sanitizeBundleIfNeeded(at: url)
                let runner = try await Leap.load(url: url)
                openAction(entry, url, runner)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
#endif
