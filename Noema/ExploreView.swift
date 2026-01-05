// ExploreView.swift
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
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
    @EnvironmentObject var localizationManager: LocalizationManager
#if os(macOS)
    @EnvironmentObject var macModalPresenter: MacModalPresenter
    @EnvironmentObject var chromeState: ExploreChromeState
#endif
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
    // Import flow state
    @State private var showImportMenu = false
    @State private var showGGUFImporter = false
    @State private var showMLXImporter = false
    @State private var pendingPickedURLs: [URL] = []
    @State private var importError: String?
    @State private var isImporting = false

    private enum ImportFormat: Equatable { case gguf, mlx }

    var body: some View { contentView }

    @ViewBuilder
    private var contentView: some View {
        listView
            .onChangeCompat(of: huggingFaceToken) { _, newValue in
                updateRegistry(newValue)
            }
            .onChangeCompat(of: filterManager.filter) { _, _ in
                // Trigger a new search when filter changes
                if !vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    vm.triggerSearch()
                }
            }
            .onChangeCompat(of: localizationManager.locale) { _, _ in
                updateRegistry(huggingFaceToken)
                Task { await vm.loadCurated(force: true) }
            }
            .task { 
                await vm.loadCurated()
                vm.setFilterManager(filterManager)
            }
#if !os(macOS)
            // Title provided by parent container
            .toolbar {
                searchModeToolbar
                importToolbar
            }
#endif
#if os(macOS)
            .onChangeCompat(of: selected) { _, detail in
                if let detail {
                    presentDetail(detail)
                } else if macModalPresenter.isPresented {
                    macModalPresenter.dismiss()
                }
            }
#else
            .sheet(item: $selected, content: detailSheet)
#endif
            .overlay { if loadingDetail { ProgressView() } }
            .overlay { if vm.isLoadingSearch { ProgressView() } }
            .overlay { searchEmptyOverlay }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                            Text(LocalizedStringKey("Importing & Scanning..."))
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
                }
            }
            .onChangeCompat(of: downloadController.navigateToDetail) { _, newValue in
                handleNavigation(newValue)
            }
            .alert(LocalizedStringKey("Error"), isPresented: hasSearchError) {
                Button(LocalizedStringKey("OK"), role: .cancel) { vm.searchError = nil }
            } message: {
                Text(vm.searchError ?? "")
            }
            .alert(LocalizedStringKey("Import Failed"), isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button(LocalizedStringKey("OK"), role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? String(localized: "Unknown error"))
            }
#if os(macOS)
            .onAppear {
                chromeState.activeSection = .models
                chromeState.searchMode = vm.searchMode
                chromeState.toggleAction = { vm.toggleMode() }
                chromeState.searchPlaceholder = LocalizedStringKey("Search models")
                chromeState.searchText = vm.searchText
                chromeState.isSearchVisible = true
                chromeState.searchSubmitAction = { vm.triggerSearch() }
            }
            .onChange(of: vm.searchMode) { newValue in
                chromeState.searchMode = newValue
            }
            .onChangeCompat(of: chromeState.searchText) { _, newValue in
                if vm.searchText != newValue {
                    vm.searchText = newValue
                }
            }
            .onChangeCompat(of: vm.searchText) { _, newValue in
                if chromeState.searchText != newValue {
                    chromeState.searchText = newValue
                }
            }
            .onDisappear {
                guard chromeState.activeSection == .models else { return }
                chromeState.toggleAction = nil
                chromeState.isSearchVisible = false
                chromeState.searchSubmitAction = nil
                chromeState.activeSection = nil
            }
            // Bring the import menu into the content area to avoid adding a toolbar that shifts layout.
            .overlay(alignment: .topTrailing) {
                importMenuButton
                    .padding(.top, AppTheme.padding)
                    .padding(.trailing, AppTheme.padding)
            }
#endif
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
#if !os(macOS) && !os(visionOS)
                case .exploreSLM:
                    if vm.searchMode != .slm {
                        vm.searchMode = .slm
                        vm.triggerSearch()
                    }
#endif
                default:
                    break
                }
            }
            // File importers for iOS/visionOS (mac uses NSOpenPanel; tvOS lacks Files access)
            #if !os(tvOS)
            .fileImporter(
                isPresented: $showGGUFImporter,
                allowedContentTypes: ggufAllowedTypes(),
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task { await importGGUF(urls: urls) }
                }
            }
            .fileImporter(
                isPresented: $showMLXImporter,
                allowedContentTypes: [UTType.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await importMLX(directory: url) }
                }
            }
            #endif
    }

    @ViewBuilder
    private var listView: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                listContent
            }
            .padding(AppTheme.padding)
        }
        .background(AppTheme.windowBackground)
        #else
        if vm.searchMode == .slm {
            List { listContent }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.windowBackground)
                // Give the SLM list a little extra runway so the bottom
                // explore switch bar/tab bar doesn’t cover the final row.
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: slmListBottomInset)
                }
        } else {
            List { listContent }
                .searchable(text: $vm.searchText, prompt: Text(LocalizedStringKey("Search models")))
                .onSubmit(of: .search) { vm.triggerSearch() }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.windowBackground)
        }
        #endif
    }

    private func exploreCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(AppTheme.padding)
            .glassifyIfAvailable(in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .background(AppTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 4)
            .visionHoverHighlight(cornerRadius: AppTheme.cornerRadius)
    }

    private func updateRegistry(_ token: String) {
        vm.updateRegistry(CombinedRegistry(primary: HuggingFaceRegistry(token: token),
                                           extras: [ManualModelRegistry()]))
    }

    private var slmListBottomInset: CGFloat {
#if os(iOS)
        // Height budget for the Explore switch bar plus a bit of breathing room
        // so the final SLM entry can scroll fully above the menubar.
        UIConstants.defaultPadding * 2 + 40
#else
        0
#endif
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
#if os(macOS)
            .frame(minWidth: 640, idealWidth: 720, minHeight: 640, idealHeight: 760)
#endif
    }

#if os(macOS)
    private func presentDetail(_ detail: ModelDetails) {
        macModalPresenter.present(
            title: nil,
            subtitle: nil,
            showCloseButton: true,
            dimensions: MacModalDimensions(
                minWidth: 660,
                idealWidth: 720,
                maxWidth: 800,
                minHeight: 620,
                idealHeight: 700,
                maxHeight: 820
            ),
            contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
            onDismiss: { selected = nil }
        ) {
            ExploreDetailView(detail: detail)
                .environmentObject(modelManager)
                .environmentObject(chatVM)
                .environmentObject(tabRouter)
                .environmentObject(downloadController)
        }
    }
#endif

    @ViewBuilder
    private var searchEmptyOverlay: some View {
        if vm.isSearching && !vm.isLoadingSearch && vm.searchResults.isEmpty {
            VStack(spacing: 8) {
                Text(String.localizedStringWithFormat(String(localized: "No models found for '%@'"), vm.searchText))
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(emptyStateSuggestion)
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
#if canImport(LeapSDK) && !os(macOS)
        if vm.searchMode == .slm {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPadOS Grid Layout for SLM
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(vm.filteredLeap) { entry in
                            exploreCard {
                                LeapRowView(entry: entry, openAction: { e, url, runner in
                                    openLeap(entry: e, url: url, runner: runner)
                                })
                                .environmentObject(downloadController)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.padding)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } else {
                // iPhone List Layout
                Section(LocalizedStringKey("SLM Models - Liquid AI")) {
                    ForEach(vm.filteredLeap) { entry in
                        LeapRowView(entry: entry, openAction: { e, url, runner in
                            openLeap(entry: e, url: url, runner: runner)
                        })
                        .environmentObject(downloadController)
                    }
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
    private var heroSection: some View {
        if vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey("Discover Intelligence"))
                        .font(FontTheme.largeTitle)
                        .foregroundStyle(AppTheme.text)
                    Text(LocalizedStringKey("Explore the latest open-source models optimized for your Mac."))
                        .font(FontTheme.body)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.bottom, 8)
                
                let featuredModels = Array(filteredRecommended.prefix(5))
                if !featuredModels.isEmpty {
                    #if os(macOS)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
                        ForEach(featuredModels, id: \.id) { featured in
                             featuredCard(featured)
                        }
                    }
                    #else
						// iOS implementation
						VStack(spacing: 16) {
							ForEach(featuredModels, id: \.id) { featured in
								featuredCard(featured)
							}
						}
                    #endif
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func featuredCard(_ featured: ModelRecord) -> some View {
        Button { Task { await open(featured) } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey("Featured"))
                        .font(FontTheme.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: Capsule())
                    
                    if showsFitsBadge(for: featured) {
                        Text(LocalizedStringKey("Fits on your device"))
                            .font(FontTheme.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1), in: Capsule())
                    }
                    
                    if featured.pipeline_tag == "image-text-to-text" {
                        Text(LocalizedStringKey("Vision"))
                            .font(FontTheme.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.1), in: Capsule())
                    }

                    Spacer()
                }
                
                Text(featured.displayName)
                    .font(FontTheme.heading(size: 22))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(featured.publisher)
                    .font(FontTheme.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppTheme.cardFill)
            #if os(macOS)
            .frame(height: 200)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentColor.opacity(0.1))
                    .offset(x: 10, y: 10)
            }
            #else
            .frame(minHeight: 130)
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 15, x: 0, y: 8)
        }
        .visionHoverHighlight(cornerRadius: 24)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var standardSections: some View {
        if vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 24) {
                heroSection

                LazyVStack(spacing: 16) {
                    ForEach(filteredRecommended.dropFirst(5), id: \._stableKey) { record in
                         exploreCard { recordButton(record, context: .curated).buttonStyle(.plain) }
                    }
                }
            }
            #else
            // iOS implementation
            Section {
                heroSection
                    .padding(.horizontal, 0)
                    .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: AppTheme.padding, bottom: 0, trailing: AppTheme.padding))

            Section {
                ForEach(filteredRecommended.dropFirst(5), id: \._stableKey) { record in
                    recordButton(record, context: .curated)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: AppTheme.padding, bottom: 0, trailing: AppTheme.padding))
            #endif
        } else {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedStringKey("Results"))
                    .font(FontTheme.heading)
                    .foregroundStyle(AppTheme.text)
                LazyVStack(spacing: 16) {
                    ForEach(filteredSearchResults, id: \._stableKey) { record in
                        exploreCard { recordButton(record, context: .search).buttonStyle(.plain) }
                    }
                    if vm.canLoadMore {
                        ProgressView().onAppear { vm.loadNextPage() }
                    }
                }
            }
            #else
            Section(LocalizedStringKey("Results")) {
                ForEach(filteredSearchResults, id: \._stableKey) { record in
                    recordButton(record, context: .search)
                }
                if vm.canLoadMore {
                    ProgressView().onAppear { vm.loadNextPage() }
                }
            }
            #endif
        }
    }
    
    // MARK: - Filtered Results
    
    private var filteredRecommended: [ModelRecord] {
        var seen = Set<String>()
        let mode = vm.searchMode
        return vm.recommended.filter { rec in
            guard seen.insert(rec.id).inserted else { return false }

            // Respect the GGUF/MLX toggle when showing curated recommendations
            // on iOS/iPadOS so formats don’t mix across modes.
            let matchesMode: Bool = {
                switch mode {
                case .gguf:
                    return rec.formats.contains(.gguf)
                case .mlx:
                    // Allow MLX-tagged repos and common MLX publisher namespaces
                    return rec.formats.contains(.mlx)
                        || rec.id.hasPrefix("mlx-community/")
                        || rec.id.hasPrefix("lmstudio-community/")
                case .slm:
                    // Curated GGUF/MLX section isn’t shown in SLM mode, but keep permissive
                    // behavior here to avoid surprising empty lists if reused.
                    return true
                }
            }()

            return matchesMode && filterManager.shouldIncludeModel(rec)
        }
    }

    private var emptyStateSuggestion: String {
        // Replace placeholder in localized bullet list with the current mode hint.
        String(format: String(localized: "Try bullet"), modeSwitchHint)
    }

    private var modeSwitchHint: String {
#if os(macOS)
        return String(localized: "Switching between GGUF/MLX modes")
#else
        return DeviceGPUInfo.supportsGPUOffload
        ? String(localized: "Switching between GGUF/MLX modes")
        : String(localized: "Switching between GGUF/SLM modes")
#endif
    }

    private var filteredSearchResults: [ModelRecord] {
        var seen = Set<String>()
        return vm.searchResults.filter { rec in
            filterManager.shouldIncludeModel(rec) && seen.insert(rec.id).inserted
        }
    }

    private enum RecordBadgeContext { case curated, search }

    /// Conservative gate for the “Fits on your device” badge so it only shows
    /// when we have a curated minimum RAM hint that is comfortably under the
    /// device’s per‑app budget. This avoids promising a fit when the detailed
    /// quant estimates in the detail sheet would later show a red X.
    private func showsFitsBadge(for record: ModelRecord) -> Bool {
        guard record.hasInstallableQuant, let minRAM = record.minRAMBytes else { return false }
        guard let budget = DeviceRAMInfo.current().conservativeLimitBytes() else { return false }

        let safetyMargin = 0.92
        return Double(minRAM) <= Double(budget) * safetyMargin
    }

    @ViewBuilder
    private func recordButton(_ record: ModelRecord, context: RecordBadgeContext) -> some View {
        let showsVisionEye = context == .search
        let showsVisionLabel = context == .curated

        Button { Task { await open(record) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(record.displayName)
                        .font(FontTheme.body)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.text)
                    // Vision badge (non-blocking) — hidden while multimodal UI is disabled.
                    // On iOS in particular, surface an immediate badge when the Hub pipeline
                    // already identifies the repo as VLM to avoid waiting for metadata fetches.
                    if UIConstants.showMultimodalUI {
                        if record.pipeline_tag == "image-text-to-text" {
                            if showsVisionEye {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.yellow, lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                    Image(systemName: "eye.fill")
                                        .foregroundColor(Color.yellow)
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .accessibilityLabel(LocalizedStringKey("Vision-capable model"))
                                .help(LocalizedStringKey("Vision-capable model"))
                            }
                        } else {
                            VisionBadge(repoId: record.id, token: huggingFaceToken, showsIcon: showsVisionEye)
                        }
                    }
                    
                    if showsFitsBadge(for: record) {
                        Text(LocalizedStringKey("Fits on your device"))
                            .font(FontTheme.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1), in: Capsule())
                    }
                    
                    if showsVisionLabel && record.pipeline_tag == "image-text-to-text" {
                        Text(LocalizedStringKey("Vision"))
                            .font(FontTheme.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.1), in: Capsule())
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
                        .font(FontTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                if !record.hasInstallableQuant {
                    Text(LocalizedStringKey("No quant files available"))
                        .font(FontTheme.caption)
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
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            Button(action: { vm.toggleMode() }) {
                Text(vm.searchMode.rawValue)
            }
            .buttonStyle(.glass(color: searchModeColor, isActive: true))
            .guideHighlight(.exploreModelToggle)
        }
        #else
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { vm.toggleMode() }) {
                Text(vm.searchMode.rawValue)
            }
            .buttonStyle(.glass(color: searchModeColor, isActive: true))
            .guideHighlight(.exploreModelToggle)
        }
        #endif
    }

    private var searchModeGradient: LinearGradient {
        switch vm.searchMode {
        case .gguf:
            return ModelFormat.gguf.tagGradient
        case .mlx:
            return ModelFormat.mlx.tagGradient
        case .slm:
#if os(macOS)
            return ModelFormat.mlx.tagGradient
#else
            return ModelFormat.slm.tagGradient
#endif
        }
    }
    private var searchModeColor: Color {
        switch vm.searchMode {
        case .gguf: return .blue
        case .mlx: return .purple
        case .slm:
#if os(macOS)
            return .purple
#else
            return .orange
#endif
        }
    }

    // MARK: - Import Toolbar

    @ToolbarContentBuilder
    private var importToolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .automatic) { EmptyView() }
        #else
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button(action: { presentImporter(.gguf) }) {
                    Label(LocalizedStringKey("Import GGUF"), systemImage: "tray.and.arrow.down.fill")
                }
                if supportsMLXImport {
                    Button(action: { presentImporter(.mlx) }) {
                        Label(LocalizedStringKey("Import MLX"), systemImage: "bolt.fill")
                    }
                }
            } label: {
                Label(LocalizedStringKey("Import"), systemImage: "square.and.arrow.down")
            }
            .accessibilityLabel(LocalizedStringKey("Import"))
        }
        #endif
    }

    #if os(macOS)
    private var importMenuButton: some View {
        Menu {
            Button(action: { presentImporter(.gguf) }) {
                Label(LocalizedStringKey("Import GGUF"), systemImage: "tray.and.arrow.down.fill")
            }
            if supportsMLXImport {
                Button(action: { presentImporter(.mlx) }) {
                    Label(LocalizedStringKey("Import MLX"), systemImage: "bolt.fill")
                }
            }
        } label: {
            Label(LocalizedStringKey("Import"), systemImage: "square.and.arrow.down")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .help(LocalizedStringKey("Import"))
    }
    #endif

    private var supportsMLXImport: Bool {
        #if os(iOS) || os(visionOS) || os(tvOS)
        return DeviceGPUInfo.supportsGPUOffload
        #else
        return true
        #endif
    }

    private func ggufAllowedTypes() -> [UTType] {
        var types: [UTType] = []
        if let gguf = UTType(filenameExtension: "gguf") { types.append(gguf) }
        types.append(.data)
        #if !os(tvOS)
        types.append(.folder)
        #endif
        return types
    }

    @MainActor
    private func presentImporter(_ format: ImportFormat) {
#if os(tvOS)
        importError = String(localized: "Model import isn’t available on tvOS.")
        return
#elseif os(macOS)
        switch format {
        case .gguf:
            presentMacGGUFImporter()
        case .mlx:
            guard supportsMLXImport else { return }
            presentMacMLXImporter()
        }
#else
        switch format {
        case .gguf:
            showGGUFImporter = true
        case .mlx:
            if supportsMLXImport { showMLXImporter = true }
        }
#endif
    }

#if os(macOS)
    @MainActor
    private func presentMacGGUFImporter() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ggufAllowedTypes()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = String(localized: "Import")

        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { await importGGUF(urls: urls) }
        }
    }

    @MainActor
    private func presentMacMLXImporter() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Import")

        if panel.runModal() == .OK, let url = panel.urls.first {
            Task { await importMLX(directory: url) }
        }
    }
#endif

    @MainActor
    private func open(_ record: ModelRecord) async {
        if openingModelId == record.id { return }
        openingModelId = record.id
        defer { openingModelId = nil }

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
        let architectureLabels = LocalModel.architectureLabels(for: url, format: .slm, modelID: entry.slug)
        let local = modelManager.downloadedModels.first(where: { $0.modelID == entry.slug }) ??
            LocalModel(
                modelID: entry.slug,
                name: entry.displayName,
                url: url,
                quant: "",
                architecture: architectureLabels.display,
                architectureFamily: architectureLabels.family,
                format: .slm,
                sizeGB: Double(entry.sizeBytes) / 1_073_741_824.0,
                isMultimodal: false,
                isToolCapable: false,
                isDownloaded: true,
                downloadDate: Date(),
                lastUsedDate: nil,
                isFavourite: false,
                totalLayers: 0,
                moeInfo: nil
            )
        modelManager.updateSettings(ModelSettings.default(for: .slm), for: local)
        modelManager.markModelUsed(local)
        tabRouter.selection = .chat
    }
#endif
}

private struct VisionBadge: View {
    let repoId: String
    let token: String
    let showsIcon: Bool
    @State private var isVision = false
    @EnvironmentObject var filterManager: ModelTypeFilterManager

    var body: some View {
        Group {
            if isVision && showsIcon {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    Image(systemName: "eye.fill")
                        .foregroundColor(Color.yellow)
                        .font(.system(size: 11, weight: .semibold))
                }
                .help(LocalizedStringKey("Vision-capable model"))
            } else if isVision {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .onAppear {
            updateFromFilter()
        }
        .onReceive(filterManager.$visionStatusVersion) { _ in
            updateFromFilter()
        }
        .task(id: repoId) {
            await ensureVisionStatus()
        }
    }

    private func updateFromFilter() {
        if let status = filterManager.knownVisionStatus(for: repoId) {
            isVision = status
        }
    }

    private func ensureVisionStatus() async {
        let known = await MainActor.run { filterManager.knownVisionStatus(for: repoId) }
        if let known {
            await MainActor.run { isVision = known }
            return
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let vision = await VisionModelDetector.isVisionModel(repoId: repoId, token: trimmedToken.isEmpty ? nil : trimmedToken)
        await MainActor.run {
            filterManager.updateVisionStatus(repoId: repoId, isVision: vision)
            isVision = vision
        }
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
                    Text(LocalizedStringKey("Tools"))
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
#if os(macOS)
    @Environment(\.macModalDismiss) private var macModalDismiss
#endif
    @State private var progressMap: [String: Double] = [:]
    @State private var speedMap: [String: Double] = [:]
    @State private var downloading: Set<String> = []
    @AppStorage("huggingFaceToken") private var huggingFaceToken = ""
    @State private var quantSort: QuantSortOption = .quant
    @State private var metaVersion: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heroHeader

                    infoCard(title: LocalizedStringKey("Available Quantizations"), trailing: {
                        Picker(LocalizedStringKey("Sort"), selection: $quantSort) {
                            ForEach(QuantSortOption.allCases, id: \.self) { opt in
                                Text(opt.titleKey).tag(opt)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel(LocalizedStringKey("Sort quantizations"))
                    }) {
                        if eligibleQuants.isEmpty {
                            Text(LocalizedStringKey("No ≥Q3 quants are available for this model."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(sortedQuants) { q in
                                    quantTile(for: q)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 28)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.detailSheetBackground.ignoresSafeArea())
            #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(LocalizedStringKey("Close")) { close() } }
            }
            #endif
            .onAppear {
                if downloadController.items.contains(where: { $0.detail.id == detail.id }) {
                    downloadController.showOverlay = false
                }
            }
            .task(id: detail.id) {
                // Ensure Hub metadata (gguf.architecture) is cached for badges like MoE
                let token = huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = await HuggingFaceMetadataCache.fetchAndCache(repoId: detail.id, token: token.isEmpty ? nil : token)
                metaVersion &+= 1
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

    private var sortedQuants: [QuantInfo] {
        switch quantSort {
        case .quant:
            return eligibleQuants.sorted { a, b in
                quantSortKey(a) < quantSortKey(b)
            }
        case .sizeSmall:
            return eligibleQuants.sorted { $0.sizeBytes < $1.sizeBytes }
        case .sizeLarge:
            return eligibleQuants.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    private func quantSortKey(_ q: QuantInfo) -> (Int, Int, Int, Int, Int, String) {
        // Lower tuple compares first; smaller values rank higher
        let label = q.label.uppercased()
        let bits = q.inferredBitWidth ?? 999
        let formatRank: Int = {
            switch q.format {
            case .gguf: return 0
            case .mlx: return 5
            case .slm: return 6
            case .apple: return 7
            }
        }()

        // Variant and family ranking targeted for common GGUF patterns
        // Priority: K_M → K_L → K_S → K (no suffix) → _0 → _1 → IQ* → others
        let hasKM = label.contains("_K_M")
        let hasKL = label.contains("_K_L")
        let hasKS = label.contains("_K_S")
        let hasKOnly = label.contains("_K") && !(hasKM || hasKL || hasKS)
        let has0 = label.contains("_0")
        let has1 = label.contains("_1")
        let isIQ = label.contains("IQ")

        let groupRank: Int = {
            if hasKM { return 0 }
            if hasKL { return 1 }
            if hasKS { return 2 }
            if hasKOnly { return 3 }
            if has0 { return 4 }
            if has1 { return 5 }
            if isIQ { return 6 }
            return 9
        }()

        // Secondary within-group rank (e.g., distinguish 0 vs 1, or prefer KM over KL over KS already handled)
        let variantRank: Int = {
            if has0 { return 0 }
            if has1 { return 1 }
            return 0
        }()

        // Some labels include model scale (e.g., Q3_K_M_XS). Prefer XS/XXS before larger variants when bits tie
        let scaleRank: Int = {
            if label.contains("_XXS") { return 0 }
            if label.contains("_XS") { return 1 }
            if label.contains("_S") { return 2 }
            if label.contains("_M") { return 3 }
            if label.contains("_L") { return 4 }
            if label.contains("_XL") { return 5 }
            return 3
        }()

        return (formatRank, groupRank, bits, variantRank, scaleRank, label)
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

    private func close() {
#if os(macOS)
        macModalDismiss()
#else
        dismiss()
#endif
    }

    @MainActor
    private func useModel(info: QuantInfo) async {
        let url = fileURL(for: info)
        let name = url.deletingPathExtension().lastPathComponent
        
        // Detect vision capability strictly via projector presence for GGUF models
        let token = huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let meta = HuggingFaceMetadataCache.cached(repoId: detail.id)
        var isVision = meta?.hasProjectorFile ?? false

        if !isVision {
            switch info.format {
            case .gguf:
                isVision = ModelVisionDetector.guessLlamaVisionModel(from: url)
                if !isVision {
                    isVision = await VisionModelDetector.isVisionModel(repoId: detail.id, token: token.isEmpty ? nil : token)
                }
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

        let moeInfo: MoEInfo?
        switch info.format {
        case .gguf, .mlx:
            moeInfo = ModelScanner.moeInfo(for: url, format: info.format)
        case .slm, .apple:
            moeInfo = nil
        }
        let architectureLabels = LocalModel.architectureLabels(for: url, format: info.format, modelID: detail.id)
        let local = LocalModel(
            modelID: detail.id,
            name: name,
            url: url,
            quant: info.label,
            architecture: architectureLabels.display,
            architectureFamily: architectureLabels.family,
            format: info.format,
            sizeGB: Double(info.sizeBytes) / 1_073_741_824.0,
            isMultimodal: isVision,
            isToolCapable: isToolCapable,
            isDownloaded: true,
            downloadDate: Date(),
            lastUsedDate: nil,
            isFavourite: false,
            totalLayers: ModelScanner.layerCount(for: url, format: info.format),
            moeInfo: moeInfo
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
        close()
    }
}

// MARK: - Import helpers

extension ExploreView {
    @MainActor
    private func importGGUF(urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        
        do {
            let fm = FileManager.default
            let now = Date()
            // Flatten: include gguf files directly selected and any gguf within selected folders
            var ggufFiles: [URL] = []
            for u in urls {
                let scoped = u.startAccessingSecurityScopedResource()
                defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                    if let items = try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil) {
                        ggufFiles.append(contentsOf: items.filter { $0.pathExtension.lowercased() == "gguf" })
                    }
                } else if u.pathExtension.lowercased() == "gguf" {
                    ggufFiles.append(u)
                }
            }
            // Partition base weights vs projector files
            func isProjector(_ url: URL) -> Bool {
                let name = url.lastPathComponent.lowercased()
                return name.contains("mmproj") || name.contains("projector") || name.contains("image_proj")
            }
            let baseWeights = ggufFiles.filter { !isProjector($0) }
            let projectors = ggufFiles.filter { isProjector($0) }
            
            guard !baseWeights.isEmpty else {
                importError = "No GGUF model files found in selection."
                return
            }

            for weight in baseWeights {
                let scopedWeight = weight.startAccessingSecurityScopedResource()
                defer { if scopedWeight { weight.stopAccessingSecurityScopedResource() } }

                // Derive repo name (strip quant token from filename when possible)
                let baseName = weight.deletingPathExtension().lastPathComponent
                let quantToken = QuantExtractor.shortLabel(from: baseName, format: .gguf)
                let repoName = deriveRepoName(from: baseName, removing: quantToken)
                let modelID = "local/\(repoName)"
                // Destination directory for this model
                let destDir = InstalledModelsStore.baseDir(for: .gguf, modelID: modelID)
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

                // Copy weight file
                let destWeight = uniqueDestination(for: destDir.appendingPathComponent(weight.lastPathComponent))
                try safeCopy(from: weight, to: destWeight)

                // Copy any selected projector files alongside
                for proj in projectors {
                    let scopedProj = proj.startAccessingSecurityScopedResource()
                    defer { if scopedProj { proj.stopAccessingSecurityScopedResource() } }

                    let destProj = uniqueDestination(for: destDir.appendingPathComponent(proj.lastPathComponent))
                    try? safeCopy(from: proj, to: destProj)
                }

                // Resolve canonical URL (prefers first valid .gguf inside directories)
                let canonical = InstalledModelsStore.canonicalURL(for: destWeight, format: .gguf)
                // Compute metadata
                let size = (try? fm.attributesOfItem(atPath: canonical.path)[.size] as? Int64) ?? 0
                let layers = ModelScanner.layerCount(for: canonical, format: .gguf)
                
                // Vision detection: check for external projector OR embedded projector (e.g. Llama 3.2 Vision)
                var isVision = ProjectorLocator.hasProjectorFile(in: canonical.deletingLastPathComponent())
                if !isVision {
                    isVision = ModelVisionDetector.guessLlamaVisionModel(from: canonical)
                }
                
                let isToolCap = ToolCapabilityDetector.isToolCapableLocal(url: canonical, format: .gguf)
                let moeInfo = ModelScanner.moeInfo(for: canonical, format: .gguf) ?? .denseFallback
                // Persist MoE cache asynchronously
                Task { await MoEDetectionStore.shared.update(info: moeInfo, modelID: modelID, quantLabel: quantToken) }

                let installed = InstalledModel(
                    modelID: modelID,
                    quantLabel: quantToken,
                    url: canonical,
                    format: .gguf,
                    sizeBytes: size,
                    lastUsed: nil,
                    installDate: now,
                    checksum: nil,
                    isFavourite: false,
                    totalLayers: layers,
                    isMultimodal: isVision,
                    isToolCapable: isToolCap,
                    moeInfo: moeInfo
                )
                modelManager.install(installed)
            }
        } catch {
            if let err = error as? CocoaError,
               (err.code == .fileReadNoPermission || err.code == .fileWriteNoPermission) {
                let path = (err.userInfo[NSFilePathErrorKey] as? String) ?? "selected files"
                importError = "Import failed: Permission denied for \(path). Please allow access when prompted or move the files to a readable location."
            } else {
                importError = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func importMLX(directory: URL) async {
        guard supportsMLXImport else { return }
        isImporting = true
        defer { isImporting = false }
        
        do {
            let scoped = directory.startAccessingSecurityScopedResource()
            defer { if scoped { directory.stopAccessingSecurityScopedResource() } }

            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
                importError = "Selected path is not a directory."
                return
            }

            let folderName = directory.lastPathComponent
            let repoName = InstalledModelsStore.normalizedRepoName(for: .mlx, modelID: "local/\(folderName)")
            let modelID = "local/\(repoName)"
            let destDir = InstalledModelsStore.baseDir(for: .mlx, modelID: modelID)
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

            // Copy entire folder contents into destination (merge-safe)
            try copyDirectoryContents(from: directory, to: destDir)

            // Determine canonical directory
            let canonical = InstalledModelsStore.canonicalURL(for: destDir, format: .mlx)
            // Derive quant label from directory name or files
            let quantLabel = deriveMLXQuantLabel(from: directory)
            // Gather metadata
            let size = folderSize(at: canonical)
            let isVision = MLXBridge.isVLMModel(at: canonical)
            let isToolCap = ToolCapabilityDetector.isToolCapableLocal(url: canonical, format: .mlx)
            let moeInfo = ModelScanner.moeInfo(for: canonical, format: .mlx) ?? .denseFallback
            Task { await MoEDetectionStore.shared.update(info: moeInfo, modelID: modelID, quantLabel: quantLabel) }

            let installed = InstalledModel(
                modelID: modelID,
                quantLabel: quantLabel,
                url: canonical,
                format: .mlx,
                sizeBytes: size,
                lastUsed: nil,
                installDate: Date(),
                checksum: nil,
                isFavourite: false,
                totalLayers: 0,
                isMultimodal: isVision,
                isToolCapable: isToolCap,
                moeInfo: moeInfo
            )
            modelManager.install(installed)
        } catch {
            if let err = error as? CocoaError,
               (err.code == .fileReadNoPermission || err.code == .fileWriteNoPermission) {
                let path = (err.userInfo[NSFilePathErrorKey] as? String) ?? directory.path
                importError = "Import failed: Permission denied for \(path). Please allow access when prompted or move the model folder to a readable location."
            } else {
                importError = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Small utilities

    private func deriveRepoName(from baseName: String, removing token: String) -> String {
        // Remove the quant token from the original string using case-insensitive search
        if let r = baseName.range(of: token, options: .caseInsensitive) {
            var trimmed = baseName
            trimmed.removeSubrange(r)
            trimmed = trimmed.replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            trimmed = trimmed.replacingOccurrences(of: "[-_]+$", with: "", options: .regularExpression)
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? baseName : trimmed
        }
        return baseName
    }

    private func uniqueDestination(for url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var idx = 2
        while true {
            let candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) (\(idx)).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            idx += 1
        }
    }

    private func safeCopy(from: URL, to: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: to.path) {
            // Remove stale file before copying
            try? fm.removeItem(at: to)
        }
        try fm.copyItem(at: from, to: to)
    }

    private func copyDirectoryContents(from srcDir: URL, to dstDir: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)
        for item in items {
            let scoped = item.startAccessingSecurityScopedResource()
            defer { if scoped { item.stopAccessingSecurityScopedResource() } }

            let dest = dstDir.appendingPathComponent(item.lastPathComponent)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
                try copyDirectoryContents(from: item, to: dest)
            } else {
                try safeCopy(from: item, to: dest)
            }
        }
    }

    private func folderSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) {
                    total += size
                }
            }
        }
        return total
    }

    private func deriveMLXQuantLabel(from directory: URL) -> String {
        // Combine folder and file names to look for bitness tokens
        var corpus = directory.lastPathComponent
        if let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let names = items.map { $0.lastPathComponent }.joined(separator: " ")
            corpus += " " + names
        }
        let short = QuantExtractor.shortLabel(from: corpus, format: .mlx)
        return short.isEmpty ? "MLX" : short
    }
}

private extension ExploreDetailView {
    var heroHeader: some View {
        let name = (detail.id.split(separator: "/").last).map(String.init) ?? detail.id
        let owner = (detail.id.split(separator: "/").first).map(String.init)

        return VStack(alignment: .leading, spacing: 12) {
            Text(name)
                .font(FontTheme.largeTitle)
                .foregroundStyle(AppTheme.text)

            if let owner, owner != name {
                Text(owner)
                    .font(FontTheme.body)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if let summary = detail.summary, !summary.isEmpty {
                Text(summary)
                    .font(FontTheme.body)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if UIConstants.showMultimodalUI && detail.isVision {
                Label(LocalizedStringKey("Vision-capable"), systemImage: "eye.fill")
                    .font(FontTheme.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.visionAccent.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.visionAccent)
                    .accessibilityLabel("Vision-capable model")
            }

            if isMoE {
                Label(LocalizedStringKey("Mixture-of-Experts"), systemImage: "circle.grid.3x3.fill")
                    .font(FontTheme.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.moeAccent.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.moeAccent)
                    .accessibilityLabel(LocalizedStringKey("Mixture-of-Experts model"))
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.cardFill)
                .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 12)
        )
    }

    private var isMoE: Bool {
        // Depend on metaVersion so the header updates after metadata fetch
        _ = metaVersion
        return detail.isMoE
    }

    func infoCard<Content: View, Trailing: View>(
        title: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(FontTheme.heading)
                    .foregroundStyle(AppTheme.text)
                Spacer(minLength: 16)
                trailing()
            }

            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.cardFill)
                .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 10)
        )
    }

    func infoCard<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        infoCard(title: title, trailing: { EmptyView() }, content: content)
    }

    func quantTile(for quant: QuantInfo) -> some View {
        QuantRow(
            canonicalID: detail.id,
            info: quant,
            progress: Binding(
                get: {
                    if let item = downloadController.items.first(where: { $0.detail.id == detail.id && $0.quant.label == quant.label }) {
                        return item.progress
                    }
                    return progressMap[quant.label, default: 0]
                },
                set: { _ in }
            ),
            speed: Binding(
                get: {
                    if let item = downloadController.items.first(where: { $0.detail.id == detail.id && $0.quant.label == quant.label }) {
                        return item.speed
                    }
                    return speedMap[quant.label, default: 0]
                },
                set: { _ in }
            ),
            downloading: downloading.contains(quant.label),
            openAction: { await useModel(info: quant) },
            downloadAction: { await download(info: quant) },
            cancelAction: { cancelDownload(label: quant.label) }
        )
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.quantTileBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.quantTileBorder, lineWidth: 1)
        )
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(info.label)
                        .font(FontTheme.body)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.text)
                }
                HStack(spacing: 6) {
                    Text(sizeText)
                        .font(FontTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(info.format.rawValue)
                        .font(FontTheme.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(info.format.tagGradient)
                        .clipShape(Capsule())
                        .foregroundColor(.white)
                }
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
                    .frame(width: downloadColumnWidth)
                    .padding(.leading, 4)
                } else {
                    // Show normal progress
                    // Give the macOS layout extra width so the progress bar matches the tile span.
                    ModernDownloadProgressView(progress: progress, speed: speed)
                        .frame(width: downloadColumnWidth)
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
                        .help(LocalizedStringKey("Retry download"))
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
                Label(LocalizedStringKey("Ready"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.badge)
                    .foregroundColor(.green)
                Button(LocalizedStringKey("Open")) { Task { await openAction() } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Button(LocalizedStringKey("Download")) { Task { await downloadAction() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private var isDownloaded: Bool {
        modelManager.downloadedModels.contains { $0.modelID == canonicalID && $0.quant == info.label }
    }

    private var downloadColumnWidth: CGFloat {
#if os(macOS)
        return 320
#else
        return 120
#endif
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(FontTheme.body)
                    .fontWeight(.medium)
                    .foregroundStyle(AppTheme.text)
                
                HStack(spacing: 6) {
                    Text(subtitleText)
                        .font(FontTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    
                    if entry.sizeBytes > 0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                        
                        ModelRAMAdvisor.badge(format: .slm, sizeBytes: entry.sizeBytes, contextLength: 4096, layerCount: nil)
                            .scaleEffect(0.9)
                    }
                }
            }
            
            Spacer()
            
            actionButton
        }
        .padding(.vertical, 8)
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
            Button(action: { start() }) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(LocalizedStringKey("Download"))
            
        case .failed(let msg):
            Button(action: { start() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    if msg == "Paused" {
                        Text("Resume")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            
        case .downloading(let p):
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(p * 100))%")
                        .font(FontTheme.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(speedText(speed))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.01, p)))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 24, height: 24)
                
                Button(action: { downloadController.cancel(itemID: entry.slug) }) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            
        case .installed:
            Button(action: { load() }) {
                Text("Open")
                    .font(FontTheme.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
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
        return size
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

private enum QuantSortOption: String, CaseIterable, Identifiable {
    case quant
    case sizeSmall
    case sizeLarge

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .quant: return LocalizedStringKey("Quant")
        case .sizeSmall: return LocalizedStringKey("Size ↑")
        case .sizeLarge: return LocalizedStringKey("Size ↓")
        }
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

#endif
