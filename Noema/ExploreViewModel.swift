// ExploreViewModel.swift
#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
import Foundation
import Combine

enum ExploreSearchMode: String {
    case gguf = "GGUF"
    case mlx = "MLX"
    case slm  = "SLM"
}
@MainActor
final class ExploreViewModel: ObservableObject {
    @Published private(set) var recommended: [ModelRecord] = []
    @Published private(set) var searchResults: [ModelRecord] = []
    @Published private(set) var leapModels: [LeapCatalogEntry] = []
    @Published private(set) var filteredLeap: [LeapCatalogEntry] = []
    @Published var searchText: String = ""
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingPage = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var isLoadingSearch = false
    @Published var searchError: String?
    @Published var searchMode: ExploreSearchMode = ExploreSearchMode.gguf {
        didSet {
#if os(visionOS)
            // The SLM mode is not presented on visionOS; coerce back to GGUF/MLX if set.
            if searchMode == .slm { searchMode = .gguf }
#endif
#if os(macOS)
            if searchMode == .slm {
                searchMode = DeviceGPUInfo.supportsGPUOffload ? .mlx : .gguf
            }
#endif
        }
    }
    
    // Filter manager for text/vision filtering
    private var filterManager: ModelTypeFilterManager?

    private var registry: any ModelRegistry
    private var searchTask: Task<Void, Never>?
    private var page = 0
    private var cancellables: Set<AnyCancellable> = []
    private var prefetchedVisionRepos: Set<String> = []

    init(registry: any ModelRegistry) {
        self.registry = registry
        $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(700), scheduler: RunLoop.main)
            .sink { [weak self] in self?.handleSearchInput($0) }
            .store(in: &cancellables)
        $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    filteredLeap = leapModels
                } else {
                    filteredLeap = leapModels.filter { $0.displayName.localizedCaseInsensitiveContains(text) || $0.slug.localizedCaseInsensitiveContains(text) }
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        // Ensure any in-flight search is cancelled to avoid retaining self via task closures.
        searchTask?.cancel()
    }
    
    func setFilterManager(_ manager: ModelTypeFilterManager) {
        self.filterManager = manager
    }

    func loadCurated(force: Bool = false) async {
        if force { recommended.removeAll() }
        if recommended.isEmpty {
            let reg = registry
            if let list = try? await reg.curated() {
                var seen = Set<String>()
                let deduped = list.filter { seen.insert($0.id).inserted }
                recommended = Self.prioritizeAuthors(in: deduped)
                prefetchVisionStatus(for: recommended)
            }
        }
        #if !os(macOS)
        if leapModels.isEmpty {
            let models = await LeapCatalogService.loadCatalog()
            // Hide VL (vision-capable) SLM bundles from the Explore SLM list
            let nonVision = models.filter { !LeapCatalogService.isVisionQuantizationSlug($0.slug) }
            leapModels = nonVision
            filteredLeap = nonVision
        }
        #endif
    }

    func details(for id: String) async -> ModelDetails? {
        let reg = registry
        return try? await reg.details(for: id)
    }

    private func handleSearchInput(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { isSearching = false; isLoadingSearch = false; return }
        guard searchMode != .slm else { return }
        isSearching = true
        searchTask = Task { [weak self] in
            await self?.search(query: trimmed, reset: true)
        }
    }

    func triggerSearch() {
        handleSearchInput(searchText)
    }

    private func search(query: String, reset: Bool) async {
        if reset {
            page = 0
            searchResults.removeAll()
        }

        isLoadingSearch = true
        let reg = registry
        let mode = searchMode
        let startPage = page
        var existing = reset ? Set<String>() : Set(searchResults.map { $0.id })

        var fetched: [ModelRecord] = []
        var unfilteredResults: [ModelRecord] = []
        var pageCount = 0
        
        // Determine if we should include vision models based on search mode and UI filter.
        // In MLX and GGUF modes, default to fetching both pipelines; the format filter
        // is applied client‑side. When the user selects the Vision filter, restrict
        // to vision pipeline only; when Text is selected, restrict to text‑generation only.
        var includeVisionModels = (mode == .gguf || mode == .mlx)
        var visionOnly = false
        if let fm = filterManager, UIConstants.showMultimodalUI {
            switch fm.filter {
            case .vision:
                includeVisionModels = true
                visionOnly = true
            case .text:
                includeVisionModels = false
            case .all:
                includeVisionModels = true
            }
        }
        
        do {
            for try await rec in reg.searchStream(query: query, page: startPage, includeVisionModels: includeVisionModels, visionOnly: visionOnly) {
                pageCount += 1
                unfilteredResults.append(rec)
                
                // Apply filtering based on mode and, if set, the Vision/Text filter.
                var shouldInclude = false
                let isVLM = (rec.pipeline_tag == "image-text-to-text")
                switch mode {
                case .gguf:
                    // In GGUF mode, only allow repos that advertise GGUF.
                    // If Vision filter is active, require VLM as well.
                    shouldInclude = rec.formats.contains(.gguf) && (!visionOnly || isVLM)
                case .mlx:
                    // In MLX mode, allow explicit MLX formats and well-known MLX namespaces.
                    // If Vision filter is active, require VLM as well.
                    let matchesMLX = rec.formats.contains(.mlx)
                        || rec.id.hasPrefix("mlx-community/")
                        || rec.id.hasPrefix("lmstudio-community/")
                    shouldInclude = matchesMLX && (!visionOnly || isVLM)
                case .slm:
                    // SLM is not used for search; keep false.
                    shouldInclude = false
                }
                
                #if DEBUG
                if !shouldInclude {
                    print("[ExploreViewModel] Filtered out: \(rec.id) formats: \(rec.formats) mode: \(mode)")
                }
                #endif
                
                if shouldInclude && existing.insert(rec.id).inserted {
                    fetched.append(rec)
                }
            }
        } catch {
            if let err = error as? HuggingFaceRegistry.RegistryError {
                if case .badStatus(let code) = err {
                    if code == 401 {
                        searchError = "Unauthorized – please check your Hugging Face token in Settings"
                    } else if code == 429 {
                        searchError = "There was an error fetching results from Hugging Face, please try again later"
                    } else {
                        searchError = err.localizedDescription
                    }
                }
            } else if let urlErr = error as? URLError {
                searchError = "Network error: \(urlErr.code.rawValue)"
            } else {
                searchError = error.localizedDescription
            }

        }
    
        // MLX should be a strict filter on every platform (macOS and iOS), matching user expectations.
        if fetched.isEmpty && !unfilteredResults.isEmpty && mode == .slm {
            print("[ExploreViewModel] No filtered results for '\(query)' in SLM mode, showing all \(unfilteredResults.count) results")
            for rec in unfilteredResults {
                if existing.insert(rec.id).inserted {
                    fetched.append(rec)
                }
            }
        }
        
        let prioritized = Self.prioritizeAuthors(in: fetched)
        // Append, then re-dedupe and re-prioritize to avoid any duplicates slipping through
        let appended = searchResults + prioritized
        var seenFinal = Set<String>()
        searchResults = appended.filter { seenFinal.insert($0.id).inserted }
        searchResults = Self.prioritizeAuthors(in: searchResults)
        canLoadMore = pageCount == 50
        isLoadingSearch = false
        prefetchVisionStatus(for: searchResults)
    }

    func loadNextPage() {
        guard searchMode != .slm && isSearching && canLoadMore && !isLoadingPage else { return }
        isLoadingPage = true
        page += 1
        searchTask = Task { [weak self, page] in
            guard let self = self else { return }
            let trimmed = self.searchText.trimmingCharacters(in: .whitespaces)
            await self.search(query: trimmed, reset: false)
            await MainActor.run { self.isLoadingPage = false }
        }
    }

    func toggleMode() {
#if os(visionOS)
        // Cycle between GGUF and MLX only; SLM is not offered on visionOS.
        switch searchMode {
        case .gguf:
            searchMode = .mlx
        default:
            searchMode = .gguf
        }
#elseif os(macOS)
        switch searchMode {
        case .gguf:
            searchMode = .mlx
        case .mlx, .slm:
            searchMode = .gguf
        }
#else
        if !DeviceGPUInfo.supportsGPUOffload {
            // Pre-A13: skip MLX entirely; cycle between GGUF and SLM only
            switch searchMode {
            case .gguf:
                searchMode = .slm
            case .mlx:
                // If somehow set to MLX, jump to GGUF
                searchMode = .gguf
            case .slm:
                searchMode = .gguf
            }
        } else {
            switch searchMode {
            case .gguf:
                searchMode = .mlx
            case .mlx:
                searchMode = .slm
            case .slm:
                searchMode = .gguf
            }
        }
#endif

        handleSearchInput(searchText)
    }

    func updateRegistry(_ reg: any ModelRegistry) {
        registry = reg
    }

    private func prefetchVisionStatus(for records: [ModelRecord]) {
        guard let filterManager else { return }
        let token = UserDefaults.standard.string(forKey: "huggingFaceToken")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authToken = (token?.isEmpty ?? true) ? nil : token
        // Prefetch for GGUF/MLX repos and also any with an explicit VLM pipeline tag so
        // Vision mode results on iOS/macOS can resolve quickly.
        let repos = records
            .filter { $0.formats.contains(.gguf) || $0.formats.contains(.mlx) || ($0.pipeline_tag == "image-text-to-text") }
            .map(\.id)
            .filter { !prefetchedVisionRepos.contains($0) }
        guard !repos.isEmpty else { return }
        prefetchedVisionRepos.formUnion(repos)
        Task {
            for repo in repos.prefix(24) {
                let known = await MainActor.run { filterManager.knownVisionStatus(for: repo) }
                if known != nil { continue }
                let isVision = await VisionModelDetector.isVisionModel(repoId: repo, token: authToken)
                await MainActor.run {
                    filterManager.updateVisionStatus(repoId: repo, isVision: isVision)
                }
            }
        }
    }
}

private extension ExploreViewModel {
    static func prioritizeAuthors(in records: [ModelRecord]) -> [ModelRecord] {
        let priorityAuthors: [String] = ["unsloth", "bartowski", "lmstudio-community", "second-state"]
        let prioritySet = Set(priorityAuthors.map { $0.lowercased() })

        let (priority, others) = records.stablePartition { rec in
            prioritySet.contains(rec.publisher.lowercased())
        }

        return priority + others
    }
}

private extension Array {
    func stablePartition(by belongsInFirstPartition: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        first.reserveCapacity(count)
        second.reserveCapacity(count)
        for element in self {
            if belongsInFirstPartition(element) {
                first.append(element)
            } else {
                second.append(element)
            }
        }
        return (first, second)
    }
}
#endif
