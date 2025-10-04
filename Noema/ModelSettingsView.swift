// ModelSettingsView.swift
import SwiftUI
import UIKit

struct ModelSettingsView: View {
    let model: LocalModel
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var walkthrough: GuidedWalkthroughManager
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false
    @AppStorage("defaultModelPath") private var defaultModelPath = ""
    @State private var settings = ModelSettings()
    @State private var layerCount: Int = 0
    @State private var scanning = false
    @State private var showKInfo = false
    @State private var showVInfo = false
    @State private var showDeleteConfirm = false
    @State private var usingDefaultGPULayers = false
    @State private var isFavourite = false
    @State private var showFavouriteLimitAlert = false
    @State private var benchmarking = false
    @State private var benchmarkResult: ModelBenchmarkResult?
    @State private var benchmarkError: String?
    @State private var benchmarkTask: Task<Void, Never>? = nil
    @State private var benchmarkTaskID: UUID? = nil
    @State private var benchmarkProgress: Double = 0
    @State private var benchmarkProgressDetail: String = "Benchmark running…"
    @Environment(\.dismiss) private var dismiss
    let loadAction: (ModelSettings) -> Void
    // File status (GGUF)
    @State private var weightsFilePath: String? = nil
    @State private var mmprojFilePath: String? = nil
    @State private var mmprojChecked: Bool = false
    @State private var filesStatusLoaded: Bool = false
    @State private var highlightAnchors: [GuidedWalkthroughManager.HighlightID: Anchor<CGRect>] = [:]

    private var availableKCacheQuants: [CacheQuant] {
        CacheQuant.allCases.filter { $0 != .iq4_nl }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(model.format.rawValue)) {
                    if model.format == .slm {
                        Text("Context Length: 4096 tokens")
                    } else {
                        Slider(value: $settings.contextLength, in: 512...32768, step: 256) {
                            Text("Context Length")
                        }
                        .guideHighlight(.modelSettingsContext)
                        Text("\(Int(settings.contextLength)) tokens")
                        // Live RAM estimate for the chosen context
                        ramEstimateView()
                        if settings.contextLength > 8192 {
                            Text("High context lengths use more memory")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    Toggle("Use as Default Model", isOn: Binding(
                        get: { defaultModelPath == model.url.path },
                        set: { newVal in
                            if newVal {
                                defaultModelPath = model.url.path
                            } else if defaultModelPath == model.url.path {
                                defaultModelPath = ""
                            }
                        }
                    ))
                    .guideHighlight(.modelSettingsDefault)

                    Toggle("Favorite Model", isOn: Binding(
                        get: { isFavourite },
                        set: { newValue in
                            if newValue {
                                if modelManager.setFavourite(model, isFavourite: true) {
                                    isFavourite = true
                                } else {
                                    isFavourite = false
                                    showFavouriteLimitAlert = true
                                }
                            } else {
                                _ = modelManager.setFavourite(model, isFavourite: false)
                                isFavourite = false
                            }
                        }
                    ))
                }

                if model.format == .gguf {
                    ggufSettings
                } else {
                    mlxSettings
                }

                benchmarkSection
                Section {
                    Button("Reset to Default Settings") {
#if canImport(UIKit) && !os(visionOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                        settings = ModelSettings.default(for: model.format)
                        // For GGUF, default to all layers by using sentinel
                        if model.format == .gguf { settings.gpuLayers = -1 }
                    }
                    .disabled(vm.loading)

                    Button("Delete Model", role: .destructive) {
#if canImport(UIKit) && !os(visionOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
                        showDeleteConfirm = true
                    }
                }
                // Files status (bottom area)
                if model.format == .gguf {
                    Section("Files") {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: (weightsFilePath != nil) ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle((weightsFilePath != nil) ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Weights")
                                Text(weightsFilePath ?? "Not found")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        HStack(alignment: .top, spacing: 8) {
                            let projectorIcon: String = {
                                if mmprojFilePath != nil { return "checkmark.circle.fill" }
                                return mmprojChecked ? "xmark.circle" : "questionmark.circle"
                            }()
                            let projectorColor: Color = {
                                if mmprojFilePath != nil { return .green }
                                return mmprojChecked ? .orange : .secondary
                            }()
                            Image(systemName: projectorIcon)
                                .foregroundStyle(projectorColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Projector (mmproj)")
                                Text(mmprojFilePath ?? (mmprojChecked ? "Not provided by repository" : "Unknown (not checked yet)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .onPreferenceChange(GuidedHighlightPreferenceKey.self) { anchors in
                highlightAnchors = anchors
            }
            .overlay {
                ModelSettingsWalkthroughOverlay(anchors: highlightAnchors)
                    .environmentObject(walkthrough)
            }
#if canImport(UIKit) && !os(visionOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .interactiveDismissDisabled(benchmarking)
            .onTapGesture { hideKeyboard() }
            .navigationTitle(model.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .disabled(benchmarking)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button(action: {
#if canImport(UIKit) && !os(visionOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                        // Save only; do not load. Close sheet.
                        modelManager.updateSettings(settings, for: model)
                        dismiss()
                    }) {
                        Text("Save")
                            .foregroundColor(.primary)
                            .opacity(0.6)
                    }
                    .buttonStyle(.plain)
                    .disabled(benchmarking)

                    Button(action: {
#if canImport(UIKit) && !os(visionOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
                        // Persist settings and trigger load
                        modelManager.updateSettings(settings, for: model)
                        loadAction(settings)
                        dismiss()
                    }) {
                        if vm.loading { ProgressView() } else { Text("Load") }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(vm.loading || benchmarking)
                }
            }
            .onAppear {
                usingDefaultGPULayers = modelManager.modelSettings[model.url.path] == nil
                settings = modelManager.settings(for: model)
                if settings.kCacheQuant == .iq4_nl {
                    settings.kCacheQuant = .f16
                }
                if let current = modelManager.downloadedModels.first(where: { $0.id == model.id }) {
                    isFavourite = current.isFavourite
                } else {
                    isFavourite = model.isFavourite
                }
                layerCount = model.totalLayers
                if layerCount == 0 {
                    scanning = true
                    Task.detached {
                        let count = ModelScanner.layerCount(for: model.url, format: model.format)
                        await MainActor.run {
                            layerCount = count
                            scanning = false
                            updateGPULayers()
                        }
                    }
                } else {
                    updateGPULayers()
                }
                refreshFileStatuses()
            }
            .onReceive(modelManager.$downloadedModels) { models in
                if let current = models.first(where: { $0.id == model.id }) {
                    isFavourite = current.isFavourite
                }
            }
            .onDisappear {
                benchmarkTask?.cancel()
                benchmarkTask = nil
                benchmarkTaskID = nil
                benchmarking = false
            }
            .onChange(of: layerCount) { _ in updateGPULayers() }
            .onChange(of: settings.gpuLayers) { _ in usingDefaultGPULayers = false }
            .alert("K Cache Quantization", isPresented: $showKInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Quantize the runtime key cache to save memory. Experimental.")
            }
            .alert("Favorite Limit Reached", isPresented: $showFavouriteLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can only favorite up to three models.")
            }
            .alert("V Cache Quantization", isPresented: $showVInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Quantize the runtime value cache to save memory when Flash Attention is enabled. Experimental.")
            }
            .alert("Delete \(model.name)?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        if modelManager.loadedModel?.id == model.id {
                            await vm.unload()
                        }
                        modelManager.delete(model)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { showDeleteConfirm = false }
            }
        }
}

    @ViewBuilder
    private func ramEstimateView() -> some View {
        let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
        let ctx = Int(settings.contextLength)
        let (estimate, budget) = ModelRAMAdvisor.estimateAndBudget(format: model.format, sizeBytes: sizeBytes, contextLength: ctx, layerCount: (layerCount > 0 ? layerCount : nil))
        let estStr = ByteCountFormatter.string(fromByteCount: estimate, countStyle: .memory)
        let budStr = budget.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "--"
        let maxCtx = ModelRAMAdvisor.maxContextUnderBudget(format: model.format, sizeBytes: sizeBytes, layerCount: (layerCount > 0 ? layerCount : nil))
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: (budget == nil || estimate <= (budget ?? Int64.max)) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor((budget == nil || estimate <= (budget ?? Int64.max)) ? .green : .orange)
                Text("Estimated working set: \(estStr) · Budget: \(budStr)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let maxCtx {
                HStack(spacing: 8) {
                    Image(systemName: "gauge")
                        .foregroundColor(.secondary)
                    Text("Max recommended context on this device: ~\(maxCtx) tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var ggufSettings: some View {
        Section("GGUF") {
            Toggle("Keep Model In Memory", isOn: $settings.keepInMemory)
            if scanning {
                VStack(alignment: .leading) { ProgressView() }
            } else if DeviceGPUInfo.supportsGPUOffload {
                VStack(alignment: .leading) {
                    // Represent sentinel (-1) as layerCount+1 on slider to show "All"
                    Slider(value: Binding(get: {
                        Double(settings.gpuLayers < 0 ? (layerCount + 1) : settings.gpuLayers)
                    }, set: { newVal in
                        let v = Int(newVal)
                        if v >= layerCount + 1 {
                            settings.gpuLayers = -1
                        } else {
                            settings.gpuLayers = max(0, min(layerCount, v))
                        }
                    }), in: 0...Double(layerCount + 1), step: 1)
                    Text(settings.gpuLayers < 0 ? "GPU Offload Layers: All/\(layerCount)" : "GPU Offload Layers: \(settings.gpuLayers)/\(layerCount)")
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("This device doesn't support GPU offload.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.yellow.opacity(0.1))
            }
            if isAdvancedMode {
                Stepper("CPU Threads: \(settings.cpuThreads)", value: $settings.cpuThreads, in: 1...ProcessInfo.processInfo.activeProcessorCount)
                if DeviceGPUInfo.supportsGPUOffload {
                    Toggle("Offload KV Cache to GPU", isOn: $settings.kvCacheOffload)
                }
                Toggle("Use mmap()", isOn: $settings.useMmap)
                HStack {
                    Text("Seed")
                    TextField("Random", text: Binding(
                        get: { settings.seed.map(String.init) ?? "" },
                        set: { newVal in
                            // Strip non-digits; drop punctuation
                            let digits = newVal.filter { $0.isNumber }
                            if let val = Int(digits) { settings.seed = val } else { settings.seed = nil }
                        }
                    ))
                    .keyboardType(.numberPad)
                }
                
                Picker(selection: $settings.kCacheQuant) {
                    ForEach(availableKCacheQuants) { q in
                        Text(q.rawValue).tag(q)
                    }
                } label: {
                    HStack {
                        Text("K Cache Quant")
                        Button {
                            showKInfo = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .pickerStyle(.menu)
                .help("Quantize the runtime key cache to save memory. Experimental.")

                Toggle("Flash Attention", isOn: $settings.flashAttention)

                if settings.flashAttention {
                    Picker(selection: $settings.vCacheQuant) {
                        ForEach(CacheQuant.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    } label: {
                        HStack {
                            Text("V Cache Quant")
                            Button {
                                showVInfo = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Quantize the runtime value cache to save memory when Flash Attention is enabled. Experimental.")
                }
            }
        }
}

    @ViewBuilder
    private var mlxSettings: some View {
        Section("MLX") {
            Text("GPU off-load is not supported for this model.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isAdvancedMode {
                HStack {
                    Text("Seed")
                    TextField("Random", text: Binding(
                        get: { settings.seed.map(String.init) ?? "" },
                        set: { newVal in
                            let digits = newVal.filter { $0.isNumber }
                            if let val = Int(digits) { settings.seed = val } else { settings.seed = nil }
                        }
                    ))
                    .keyboardType(.numberPad)
                }
                TextField("Tokenizer Path (tokenizer.json)", text: Binding(
                    get: { settings.tokenizerPath ?? "" },
                    set: { settings.tokenizerPath = $0.isEmpty ? nil : $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var benchmarkSection: some View {
        Section("Benchmark") {
            if model.format == .apple {
                Text("Benchmarking is not available for this model format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Measure real-world generation speed for this configuration. A short scripted prompt will run locally and report timing and memory usage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let fitsRAM = benchmarkFitsRAM
                    let ramGuardActive = !fitsRAM && !benchmarking
                    Button {
                        runBenchmark()
                    } label: {
                        HStack {
                            Image(systemName: "speedometer")
                            Text(benchmarking ? "Benchmarking…" : "Run Benchmark")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(benchmarking || ramGuardActive)

                    if ramGuardActive {
                        Text("This configuration exceeds the current RAM safety guard, so benchmarking is disabled.")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    if benchmarking {
                        VStack(alignment: .leading, spacing: 8) {
                            if vm.loadingProgressTracker.isLoading {
                                ProgressView(value: vm.loadingProgressTracker.progress, total: 1) {
                                    Text("Preparing benchmark…")
                                }
                                .progressViewStyle(.linear)

                                HStack {
                                    Spacer()
                                    ModelLoadingProgressView(tracker: vm.loadingProgressTracker)
                                        .padding(.top, 2)
                                    Spacer()
                                }

                                if model.format == .gguf {
                                    Text("Compiling Metal kernels for GGUF models can take up to a minute on first load.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Benchmark running…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                ProgressView(value: benchmarkProgress, total: 1)
                                    .progressViewStyle(.linear)

                                Text(benchmarkProgressDetail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button(role: .cancel) {
                            cancelBenchmark()
                        } label: {
                            HStack {
                                Image(systemName: "stop.circle")
                                Text("Cancel Benchmark")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    if let result = benchmarkResult {
                        BenchmarkSummaryCard(result: result)
                    }

                    if let error = benchmarkError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct BenchmarkSummaryCard: View {
    let result: ModelBenchmarkResult

    private var settings: ModelSettings { result.settings }
    private var format: ModelFormat { result.format }

    private struct OptimizationDescriptor: Identifiable {
        let id: String
        let title: String
        let value: String
        let icon: String
        let isActive: Bool
    }

    private var promptRateText: String {
        result.promptRate > 0 ? String(format: "%.1f tok/s", result.promptRate) : "--"
    }

    private var generationRateText: String {
        result.generationRate > 0 ? String(format: "%.1f tok/s", result.generationRate) : "--"
    }

    private var totalTimeText: String {
        String(format: "%.1fs", result.totalDuration)
    }

    private var timeToFirstText: String {
        String(format: "%.2fs", result.timeToFirstToken)
    }

    private var memoryValueText: String {
        ByteCountFormatter.string(fromByteCount: result.peakMemoryBytes, countStyle: .memory)
    }

    private var memoryDeltaText: String? {
        guard result.memoryDeltaBytes > 0 else { return nil }
        let delta = ByteCountFormatter.string(fromByteCount: result.memoryDeltaBytes, countStyle: .memory)
        return "+\(delta)"
    }

    private var optimizationBadges: [OptimizationDescriptor] {
        switch format {
        case .gguf:
            var badges: [OptimizationDescriptor] = []
            badges.append(OptimizationDescriptor(id: "flash", title: "Flash Attention", value: settings.flashAttention ? "On" : "Off", icon: "bolt.fill", isActive: settings.flashAttention))
            badges.append(OptimizationDescriptor(id: "kcache", title: "K Cache", value: settings.kCacheQuant.rawValue, icon: "memorychip", isActive: settings.kCacheQuant != .f16))
            if settings.flashAttention {
                badges.append(OptimizationDescriptor(id: "vcache", title: "V Cache", value: settings.vCacheQuant.rawValue, icon: "waveform.path.ecg", isActive: settings.vCacheQuant != .f16))
            }
            badges.append(OptimizationDescriptor(id: "kvoffload", title: "KV Offload", value: result.kvCacheOffloadActive ? "GPU" : "CPU", icon: "externaldrive.connected.to.line.below", isActive: result.kvCacheOffloadActive))
            return badges
        case .mlx, .slm, .apple:
            return []
        }
    }

    @ViewBuilder
    private var optimizationSection: some View {
        Text("Optimizations in use")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        if optimizationBadges.isEmpty {
            Text(format == .slm ? "Leap SLM models manage runtime optimizations automatically." : "This format doesn't expose tunable runtime optimizations.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(optimizationBadges) { badge in
                        OptimizationBadge(
                            title: badge.title,
                            value: badge.value,
                            icon: badge.icon,
                            isActive: badge.isActive
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest benchmark")
                        .font(.headline)
                    Text(result.completedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                optimizationSection
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    MetricTile(title: "Token processing", value: promptRateText)
                    MetricTile(title: "Token generation", value: generationRateText)
                }
                GridRow {
                    MetricTile(title: "Total time", value: totalTimeText)
                    MetricTile(title: "First token", value: timeToFirstText)
                }
                GridRow {
                    MetricTile(title: "Peak memory", value: memoryValueText, detail: memoryDeltaText)
                    MetricTile(title: "Output tokens", value: "\(result.generationTokens)")
                }
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OptimizationBadge: View {
    let title: String
    let value: String
    let icon: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption2)
                Text(value)
                    .font(.caption2.weight(.semibold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
        )
        .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.7))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String?

    init(title: String, value: String, detail: String? = nil) {
        self.title = title
        self.value = value
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModelSettingsWalkthroughOverlay: View {
    @EnvironmentObject private var manager: GuidedWalkthroughManager
    var anchors: [GuidedWalkthroughManager.HighlightID: Anchor<CGRect>]
    private let allowedSteps: Set<GuidedWalkthroughManager.Step> = [.modelSettingsIntro, .modelSettingsContext, .modelSettingsDefault]
    private let padding: CGFloat = 16
    @State private var highlightRect: CGRect = .zero
    @State private var highlightVisible = false
    @State private var pulse = false
    @State private var cardPlacement: CardPlacement = .bottom

    var body: some View {
        GeometryReader { proxy in
            overlay(in: proxy)
        }
    }

    @ViewBuilder
    private func overlay(in proxy: GeometryProxy) -> some View {
        if manager.isActive, allowedSteps.contains(manager.step) {
            let targetRect = currentHighlight(in: proxy)
            let instruction = manager.instruction(for: manager.step)
            let allowsInteraction = interactionAllowed(for: manager.step)

            ZStack {
                if highlightVisible {
                    dimmedLayer(for: highlightRect, allowsInteraction: allowsInteraction)
                    spotlightLayer(for: highlightRect)
                    haloLayer(for: highlightRect)
                } else {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .allowsHitTesting(!allowsInteraction)
                }

                VStack {
                    if cardPlacement == .top {
                        VStack(spacing: 12) {
                            instructionCard(for: instruction)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            HStack {
                                Spacer()
                                endGuideButton()
                                    .transition(.opacity)
                            }
                            .padding(.trailing, 8)
                        }
                        .padding(.horizontal, 24)
                        Spacer(minLength: 0)
                    } else {
                        Spacer(minLength: 0)
                        VStack(spacing: 12) {
                            HStack {
                                Spacer()
                                endGuideButton()
                                    .transition(.opacity)
                            }
                            .padding(.trailing, 8)
                            instructionCard(for: instruction)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 4)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                }
                .allowsHitTesting(true)
            }
            .transition(.opacity)
            .overlay(
                Color.clear
                    .onAppear {
                        startPulse()
                        updateHighlight(to: targetRect, in: proxy)
                    }
                    .onChange(of: targetRect) { updateHighlight(to: $0, in: proxy) }
                    .onChange(of: manager.step) { _ in updateHighlight(to: currentHighlight(in: proxy), in: proxy) }
            )
        } else {
            EmptyView()
        }
    }

    private func currentHighlight(in proxy: GeometryProxy) -> CGRect? {
        guard let id = manager.highlightID(for: manager.step),
              let anchor = anchors[id] else { return nil }
        var rect = proxy[anchor]
        rect = rect.insetBy(dx: -padding, dy: -padding)
        rect.origin.x = max(0, rect.origin.x)
        rect.origin.y = max(0, rect.origin.y)
        rect.size.width = min(proxy.size.width - rect.origin.x, rect.width)
        rect.size.height = min(proxy.size.height - rect.origin.y, rect.height)
        return rect
    }

    private func instructionCard(for instruction: (title: String, message: String, primary: String, secondary: String?)) -> some View {
        VStack(spacing: 16) {
            Text(instruction.title)
                .font(.system(size: 19, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(instruction.message)
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(0.85))
                .multilineTextAlignment(.center)
            Button(instruction.primary) {
                manager.performPrimaryAction()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 12)
        .animation(.easeInOut(duration: 0.3), value: manager.step)
    }

    private func dimmedLayer(for rect: CGRect, allowsInteraction: Bool) -> some View {
        let radius = highlightCornerRadius(for: rect)
        return Canvas { context, size in
            let full = Path(CGRect(origin: .zero, size: size))
            context.fill(full, with: .color(Color.black.opacity(0.52)))

            let cutout = Path(roundedRect: CGRect(x: rect.minX,
                                                  y: rect.minY,
                                                  width: rect.width,
                                                  height: rect.height),
                              cornerRadius: radius)
            context.drawLayer { inner in
                inner.blendMode = .destinationOut
                inner.fill(cutout, with: .color(.black))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(!allowsInteraction)
    }

    private func haloLayer(for rect: CGRect) -> some View {
        let radius = highlightCornerRadius(for: rect)
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(
                LinearGradient(colors: [Color.white.opacity(0.9), Color.accentColor.opacity(0.5)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                lineWidth: 3
            )
            .frame(width: rect.width + padding * 1.2, height: rect.height + padding * 1.2)
            .position(x: rect.midX, y: rect.midY)
            .shadow(color: Color.accentColor.opacity(0.35), radius: 16)
            .shadow(color: Color.white.opacity(0.25), radius: 10)
            .scaleEffect(pulse ? 1.03 : 0.97)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            .allowsHitTesting(false)
    }

    private func spotlightLayer(for rect: CGRect) -> some View {
        let innerWidth = max(1, rect.width - padding * 0.9)
        let innerHeight = max(1, rect.height - padding * 0.9)
        let radius = max(10, highlightCornerRadius(for: rect) - 6)
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [
                    Color.white.opacity(0.6),
                    Color.white.opacity(0.18)
                ],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                lineWidth: 2
            )
            .shadow(color: Color.white.opacity(0.24), radius: 8)
            .frame(width: innerWidth, height: innerHeight)
            .position(x: rect.midX, y: rect.midY)
            .blendMode(.screen)
            .compositingGroup()
            .allowsHitTesting(false)
    }

    private func highlightCornerRadius(for rect: CGRect) -> CGFloat {
        let minSide = max(1, min(rect.width, rect.height))
        if minSide < 64 { return minSide / 2 }
        return max(14, min(minSide / 3.5, 28))
    }

    private func updateHighlight(to rect: CGRect?, in proxy: GeometryProxy) {
        guard let rect else {
            if highlightVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    highlightVisible = false
                }
            }
            return
        }
        let availableAbove = rect.minY
        let availableBelow = proxy.size.height - rect.maxY
        let newPlacement: CardPlacement = availableAbove > availableBelow ? .top : .bottom

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            highlightRect = rect
            highlightVisible = true
            cardPlacement = newPlacement
        }
    }

    private func endGuideButton() -> some View {
        Button("End Guide") {
            manager.finish()
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.white.opacity(0.85))
        .foregroundStyle(.white)
    }

    private func interactionAllowed(for step: GuidedWalkthroughManager.Step) -> Bool {
        switch step {
        case .modelSettingsContext, .modelSettingsDefault:
            return true
        default:
            return false
        }
    }

    private func startPulse() {
        guard !pulse else { return }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulse.toggle()
        }
    }

    private enum CardPlacement {
        case top, bottom
    }
}

private extension ModelSettingsView {
    var benchmarkFitsRAM: Bool {
        guard model.format != .apple else { return false }
        let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
        let context = Int(settings.contextLength)
        let layerHint: Int? = layerCount > 0 ? layerCount : nil
        return ModelRAMAdvisor.fitsInRAM(
            format: model.format,
            sizeBytes: sizeBytes,
            contextLength: context,
            layerCount: layerHint
        )
    }

    func runBenchmark() {
        guard !benchmarking, model.format != .apple else { return }
#if canImport(UIKit) && !os(visionOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
        let currentSettings = settings
        benchmarkError = nil
        benchmarking = true
        benchmarkProgress = 0
        benchmarkProgressDetail = "Benchmark running…"

        let taskID = UUID()
        benchmarkTaskID = taskID
        let task = Task { [model, vm] in
            do {
                let result = try await ModelBenchmarkService.run(
                    model: model,
                    settings: currentSettings,
                    vm: vm
                ) { update in
                    benchmarkProgress = update.fraction
                    benchmarkProgressDetail = update.detail
                }
                try Task.checkCancellation()
                await MainActor.run {
                    if benchmarkTaskID == taskID {
                        benchmarkResult = result
                        benchmarkError = nil
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    if benchmarkTaskID == taskID {
                        benchmarkError = nil
                    }
                }
            } catch {
                await MainActor.run {
                    if benchmarkTaskID == taskID {
                        benchmarkError = error.localizedDescription
                        benchmarkResult = nil
                    }
                }
            }

            await MainActor.run {
                if benchmarkTaskID == taskID {
                    benchmarking = false
                    benchmarkTask = nil
                    benchmarkTaskID = nil
                }
            }
        }
        benchmarkTask = task
    }

    func cancelBenchmark() {
        guard benchmarking || benchmarkTask != nil else { return }
#if canImport(UIKit) && !os(visionOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
        benchmarkTask?.cancel()
        benchmarkTask = nil
        benchmarkTaskID = nil
        benchmarking = false
        vm.loadingProgressTracker.completeLoading()
        benchmarkProgress = 0
        benchmarkProgressDetail = "Benchmark running…"
    }

    func updateGPULayers() {
        if !DeviceGPUInfo.supportsGPUOffload {
            settings.gpuLayers = 0
            settings.kvCacheOffload = false
            return
        }
        if model.format == .gguf {
            if layerCount > 0 {
                // Preserve sentinel (-1) meaning all layers
                if settings.gpuLayers >= 0 && settings.gpuLayers > layerCount {
                    settings.gpuLayers = layerCount
                }
                if usingDefaultGPULayers && settings.gpuLayers == 0 {
                    // Default to all layers when unset
                    settings.gpuLayers = -1
                }
            }
        } else {
            settings.gpuLayers = 0
        }
    }
    
    func refreshFileStatuses() {
        guard model.format == .gguf else { return }
        let dir = model.url.deletingLastPathComponent()
        let artifactsURL = dir.appendingPathComponent("artifacts.json")
        var weightsName: String? = nil
        var projector: Any? = nil
        var checked = false
        if let data = try? Data(contentsOf: artifactsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            weightsName = obj["weights"] as? String
            projector = obj["mmproj"]
            checked = (obj["mmprojChecked"] as? Bool) ?? false
        }
        // Resolve weights path
        var resolvedWeights: String? = nil
        if let w = weightsName {
            let p = dir.appendingPathComponent(w).path
            if FileManager.default.fileExists(atPath: p) { resolvedWeights = p }
        } else {
            let p = model.url.path
            if FileManager.default.fileExists(atPath: p) { resolvedWeights = p }
        }
        // Resolve projector path
        var resolvedProj: String? = nil
        if let s = projector as? String {
            let p = dir.appendingPathComponent(s).path
            if FileManager.default.fileExists(atPath: p) { resolvedProj = p }
        }
        weightsFilePath = resolvedWeights
        mmprojFilePath = resolvedProj
        mmprojChecked = checked
        filesStatusLoaded = true
    }
}
