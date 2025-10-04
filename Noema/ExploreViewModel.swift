// ExploreViewModel.swift
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
    @Published var searchMode: ExploreSearchMode = ExploreSearchMode.gguf
    
    // Filter manager for text/vision filtering
    private var filterManager: ModelTypeFilterManager?

    private var registry: any ModelRegistry
    private var searchTask: Task<Void, Never>?
    private var page = 0
    private var cancellables: Set<AnyCancellable> = []

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
    
    func setFilterManager(_ manager: ModelTypeFilterManager) {
        self.filterManager = manager
    }

    func loadCurated() async {
        if recommended.isEmpty {
            let reg = registry
            if let list = try? await reg.curated() {
                var seen = Set<String>()
                let deduped = list.filter { seen.insert($0.id).inserted }
                recommended = Self.prioritizeAuthors(in: deduped)
            }
        }
        if leapModels.isEmpty {
            let models = await LeapCatalogService.loadCatalog()
            // Hide VL (vision-capable) SLM bundles from the Explore SLM list
            let nonVision = models.filter { !LeapCatalogService.isVisionQuantizationSlug($0.slug) }
            leapModels = nonVision
            filteredLeap = nonVision
        }
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
        
        // Determine if we should include vision models based on search mode and current filter
        var includeVisionModels = mode == .gguf // Default behavior
        var visionOnly = false
        
        // Override based on current filter if available
        if let filterManager = filterManager {
            switch filterManager.filter {
            case .all:
                includeVisionModels = mode == .gguf // Keep default behavior
                visionOnly = false
            case .text:
                includeVisionModels = false // Never include vision models for text-only filter
                visionOnly = false
            case .vision:
                includeVisionModels = false // Don't include text models
                visionOnly = true // Only vision models
            }
        }
        
        do {
            for try await rec in reg.searchStream(query: query, page: startPage, includeVisionModels: includeVisionModels, visionOnly: visionOnly) {
                pageCount += 1
                unfilteredResults.append(rec)
                
                // Apply filtering based on mode, but keep track of all results
                var shouldInclude = false
                if mode == .gguf {
                    // For GGUF mode, include only models explicitly marked as GGUF
                    shouldInclude = rec.formats.contains(.gguf)
                } else if mode == .mlx {
                    // For MLX mode, prefer mlx-community but also show MLX format models
                    shouldInclude = rec.id.hasPrefix("mlx-community/") || rec.formats.contains(.mlx)
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
        
        // If we got no results after filtering, only show all results for non-GGUF modes
        if fetched.isEmpty && !unfilteredResults.isEmpty && mode != .gguf {
            print("[ExploreViewModel] No filtered results for '\(query)' in \(mode) mode, showing all \(unfilteredResults.count) results")
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

        handleSearchInput(searchText)
    }

    func updateRegistry(_ reg: any ModelRegistry) {
        registry = reg
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
