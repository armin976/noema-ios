// ModelSettingsView.swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct ModelSettingsView: View {
    let model: LocalModel
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var walkthrough: GuidedWalkthroughManager
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false
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
    @State private var benchmarkProgressDetail: String = String(localized: "Benchmark running…")
    @Environment(\.dismiss) private var dismiss
#if os(macOS)
    @Environment(\.macModalDismiss) private var macModalDismiss
#endif
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

    private var supportsMinP: Bool { model.format == .gguf }
    private var supportsPresencePenalty: Bool { model.format == .gguf }
    private var supportsFrequencyPenalty: Bool { model.format == .gguf }
    private var supportsSpeculativeDecoding: Bool {
#if os(macOS)
        // Hide speculative decoding controls on macOS
        return false
#elseif os(visionOS)
        return false
#else
        return model.format == .gguf
#endif
    }

    private var resolvedModel: LocalModel {
        modelManager.downloadedModels.first(where: { $0.id == model.id }) ?? model
    }

    private var resolvedMoEInfo: MoEInfo? {
        resolvedModel.moeInfo
    }

    private var allowsMoEExpertSelection: Bool {
        switch model.format {
        case .mlx:
            return false
        default:
            return true
        }
    }

    private var effectiveMoEInfo: MoEInfo? {
        guard var info = resolvedMoEInfo else { return nil }
        guard info.isMoE else { return info }
        guard allowsMoEExpertSelection else { return info }
        // Preserve the true expert pool size for sizing calculations but
        // carry the user's active-expert choice through `defaultUsed` so
        // RAM estimates scale upward when more experts are selected.
        info.defaultUsed = resolvedActiveExperts(for: info)
        return info
    }

    private func fallbackActiveExperts(for info: MoEInfo) -> Int {
        let total = max(1, info.expertCount)
        if let recommended = info.defaultUsed, recommended > 0 {
            let sanitized = min(max(1, recommended), total)
            if sanitized < total { return sanitized }
        }
        guard total > 1 else { return 1 }
        let half = max(1, Int((Double(total) * 0.5).rounded(.toNearestOrAwayFromZero)))
        if half < total { return half }
        return max(1, total - 1)
    }

    private func resolvedActiveExperts(for info: MoEInfo) -> Int {
        let total = max(1, info.expertCount)
        let fallback = fallbackActiveExperts(for: info)
        let selected = settings.moeActiveExperts ?? fallback
        return min(max(1, selected), total)
    }

    private func updateMoESettingsIfNeeded(with info: MoEInfo?) {
        guard let info else { return }
        if let total = info.totalLayerCount, total > 0 {
            if layerCount <= 0 || layerCount < total {
                layerCount = total
            }
        }
        if !info.isMoE {
            if settings.moeActiveExperts != nil {
                settings.moeActiveExperts = nil
            }
            return
        }
        if !allowsMoEExpertSelection {
            if settings.moeActiveExperts != nil {
                settings.moeActiveExperts = nil
            }
            return
        }
        let resolved = resolvedActiveExperts(for: info)
        if settings.moeActiveExperts != resolved {
            settings.moeActiveExperts = resolved
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
        }
    }

    private var mainContent: some View {
        settingsContainer
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
        #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        close()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .disabled(benchmarking)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button(action: {
#if canImport(UIKit) && !os(visionOS)
                        Haptics.impact(.light)
#endif
                        // Save only; do not load. Close sheet.
                        modelManager.updateSettings(settings, for: model)
                        close()
                    }) {
                        Text("Save")
                            .foregroundColor(.primary)
                            .opacity(0.6)
                    }
                    .buttonStyle(.plain)
                    .disabled(benchmarking)

                    Button(action: {
#if canImport(UIKit) && !os(visionOS)
                        Haptics.impact(.medium)
#endif
                        // Persist settings and trigger load
                        modelManager.updateSettings(settings, for: model)
                        loadAction(settings)
                        close()
                    }) {
                        if vm.loading { ProgressView() } else { Text("Load") }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(vm.loading || benchmarking)
                }
            }
        #endif
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
                            if count > 0 {
                                layerCount = count
                            }
                            scanning = false
                            updateGPULayers()
                        }
                    }
                } else {
                    updateGPULayers()
                }
                updateMoESettingsIfNeeded(with: resolvedMoEInfo)
                refreshFileStatuses()
            }
            .onReceive(modelManager.$downloadedModels) { models in
                if let current = models.first(where: { $0.id == model.id }) {
                    isFavourite = current.isFavourite
                    updateMoESettingsIfNeeded(with: current.moeInfo)
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
            .alert(
                String.localizedStringWithFormat(String(localized: "Delete %@?"), model.name),
                isPresented: $showDeleteConfirm
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        if modelManager.loadedModel?.id == model.id {
                            await vm.unload()
                        }
                        modelManager.delete(model)
                        close()
                    }
                }
                Button("Cancel", role: .cancel) { showDeleteConfirm = false }
            }
    }

#if os(macOS)
private struct MacSettingsBlock<Content: View>: View {
    let title: String?
    let format: ModelFormat?
    let iconName: String?
    let content: Content

    init(title: String? = nil, format: ModelFormat? = nil, iconName: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.format = format
        self.iconName = iconName
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if title != nil || format != nil || iconName != nil {
                HStack(spacing: 12) {
                    if let format {
                        ModelFormatTagView(format: format)
                    } else if let iconName {
                        Image(systemName: iconName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    if let title {
                        Text(title)
                            .font(FontTheme.heading(size: 20))
                            .foregroundStyle(AppTheme.text)
                    }

                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
        )
        .controlSize(.large)
    }
}

private struct ModelFormatTagView: View {
    let format: ModelFormat

    var body: some View {
        Text(format.rawValue.uppercased())
            .font(FontTheme.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(format.tagGradient)
            .clipShape(Capsule())
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}
#endif

    @ViewBuilder
    private var settingsContainer: some View {
#if os(macOS)
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 24) {
                        MacSettingsBlock(title: "Overview", format: model.format, iconName: "square.grid.2x2") {
                            generalSettingsContent
                        }

                        if model.format == .gguf {
                            MacSettingsBlock(title: "GGUF", iconName: "circle.hexagongrid") {
                                ggufSettingsContent
                            }
                        } else {
                            MacSettingsBlock(title: model.format.rawValue, iconName: "slider.horizontal.2.square") {
                                mlxSettingsContent
                            }
                        }

                        if isAdvancedMode {
                            MacSettingsBlock(title: "Sampling", iconName: "slider.horizontal.3") {
                                samplingSectionContent
                            }
#if os(macOS)
                            if supportsSpeculativeDecoding {
                                MacSettingsBlock(title: "Speculative Decoding", iconName: "sparkles") {
                                    speculativeDecodingContent
                                }
                            }
#endif
                        }

                        MacSettingsBlock(title: "Benchmark", iconName: "speedometer") {
                            benchmarkSectionContent
                        }

                        MacSettingsBlock(title: "Maintenance", iconName: "arrow.clockwise") {
                            resetActionsContent
                        }

                        if model.format == .gguf {
                            MacSettingsBlock(title: "Files", iconName: "externaldrive") {
                                filesSectionContent
                            }
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            // Inline action bar to avoid window toolbar on macOS
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button {
                        close()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.plain)
                    .disabled(benchmarking)

                    Spacer()

                    Button(action: {
                        modelManager.updateSettings(settings, for: model)
                        close()
                    }) {
                        Text("Save")
                            .foregroundColor(.primary)
                            .opacity(0.75)
                    }
                    .buttonStyle(.plain)
                    .disabled(benchmarking)

                    Button(action: {
                        modelManager.updateSettings(settings, for: model)
                        loadAction(settings)
                        close()
                    }) {
                        if vm.loading { ProgressView() } else { Text("Load") }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(vm.loading || benchmarking)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
#else
        Form {
            settingsSections
        }
#endif
    }

    @ViewBuilder
    private var settingsSections: some View {
        Section(header: Text(model.format.rawValue)) {
            generalSettingsContent
        }

        if model.format == .gguf {
            ggufSettings
        } else {
            mlxSettings
        }

        if isAdvancedMode {
            samplingSection
        }

        // Speculative decoding UI intentionally hidden on macOS
        #if os(macOS)
        // no-op
        #endif

        benchmarkSection

        Section {
            resetActionsContent
        }

        if model.format == .gguf {
            filesSection
        }
    }

    @ViewBuilder
    private var generalSettingsContent: some View {
        if model.format == .slm {
            Text("Context Length: 4096 tokens")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Context Length")
                        .font(FontTheme.subheadline)
                        .foregroundStyle(AppTheme.text)
                    Slider(value: $settings.contextLength, in: 512...32768, step: 256)
                        .guideHighlight(.modelSettingsContext)
                }

                Text("\(Int(settings.contextLength)) tokens")

                ramEstimateView()

                if settings.contextLength > 8192 {
                    Text("High context lengths use more memory")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }

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

    @ViewBuilder
    private var resetActionsContent: some View {
        Button("Reset to Default Settings") {
#if canImport(UIKit) && !os(visionOS)
            Haptics.impact(.light)
#endif
            settings = ModelSettings.default(for: model.format)
            if model.format == .gguf { settings.gpuLayers = -1 }
            updateMoESettingsIfNeeded(with: resolvedMoEInfo)
        }
        .disabled(vm.loading)

        Button("Delete Model", role: .destructive) {
#if canImport(UIKit) && !os(visionOS)
            Haptics.impact(.medium)
#endif
            showDeleteConfirm = true
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        Section("Files") {
            filesSectionContent
        }
    }

    @ViewBuilder
    private var filesSectionContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: (weightsFilePath != nil) ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle((weightsFilePath != nil) ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Weights")
                Text(weightsFilePath ?? String(localized: "Not found"))
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
                Text(
                    mmprojFilePath ?? (mmprojChecked
                                       ? String(localized: "Not provided by repository")
                                       : String(localized: "Unknown (not checked yet)"))
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        if model.isMultimodal {
            VStack(alignment: .leading, spacing: 4) {
                if let mmprojFilePath {
                    Label {
                        Text("Projector downloaded automatically from Hugging Face. Keep this file alongside the weights so vision remains available.")
                    } icon: {
                        Image(systemName: "wand.and.rays")
                            .foregroundStyle(Color.visionAccent)
                    }
                } else if mmprojChecked {
                    Label {
                        Text("Noema could not find a projector in the repository. If the model advertises vision, ensure the mmproj file is present in the same folder as the weights.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label {
                        Text("Vision models require a companion projector (.mmproj). Noema will fetch it automatically the next time you download this model.")
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func ramEstimateView() -> some View {
        let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
        let ctx = Int(settings.contextLength)
        let locale = LocalizationManager.preferredLocale()
        let (estimate, budget) = ModelRAMAdvisor.estimateAndBudget(
            format: model.format,
            sizeBytes: sizeBytes,
            contextLength: ctx,
            layerCount: (layerCount > 0 ? layerCount : nil),
            moeInfo: effectiveMoEInfo
        )
        let estStr = ByteCountFormatter.string(fromByteCount: estimate, countStyle: .memory)
        let budStr = budget.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "--"
        let maxCtx = ModelRAMAdvisor.maxContextUnderBudget(
            format: model.format,
            sizeBytes: sizeBytes,
            layerCount: (layerCount > 0 ? layerCount : nil),
            moeInfo: effectiveMoEInfo
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: (budget == nil || estimate <= (budget ?? Int64.max)) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor((budget == nil || estimate <= (budget ?? Int64.max)) ? .green : .orange)
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "Estimated working set: %@ · Budget: %@", locale: locale),
                        estStr,
                        budStr
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let maxCtx {
                HStack(spacing: 8) {
                    Image(systemName: "gauge")
                        .foregroundColor(.secondary)
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "Max recommended context on this device: ~%@ tokens", locale: locale),
                            "\(maxCtx)"
                        )
                    )
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
            ggufSettingsContent
        }
    }

    @ViewBuilder
    private var ggufSettingsContent: some View {
        Toggle("Keep Model In Memory", isOn: $settings.keepInMemory)
        if scanning {
            VStack(alignment: .leading) { ProgressView() }
        } else if DeviceGPUInfo.supportsGPUOffload {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("GPU Offload Layers"))
                        .font(FontTheme.subheadline)
                        .foregroundStyle(AppTheme.text)
                    Slider(
                        value: Binding(get: {
                            Double(settings.gpuLayers < 0 ? (layerCount + 1) : settings.gpuLayers)
                        }, set: { newVal in
                            let v = Int(newVal)
                            if v >= layerCount + 1 {
                                settings.gpuLayers = -1
                            } else {
                                settings.gpuLayers = max(0, min(layerCount, v))
                            }
                        }),
                        in: 0...Double(layerCount + 1),
                        step: 1
                    )
                }
                let offloadValue = settings.gpuLayers < 0 ? String(localized: "All") : "\(settings.gpuLayers)"
                let layerCountLabel = "\(layerCount)"
                Text(String.localizedStringWithFormat(
                    String(localized: "GPU Offload Layers: %@/%@"),
                    offloadValue,
                    layerCountLabel
                ))
                    .font(.footnote.monospacedDigit())
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(LocalizedStringKey("This device doesn't support GPU offload."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsWarningBackground()
        }
        if let moeInfo = resolvedMoEInfo {
            moeSettings(for: moeInfo)
        }
        if isAdvancedMode {
            Stepper(
                String.localizedStringWithFormat(String(localized: "CPU Threads: %@"), "\(settings.cpuThreads)"),
                value: $settings.cpuThreads,
                in: 1...ProcessInfo.processInfo.activeProcessorCount
            )
            if DeviceGPUInfo.supportsGPUOffload {
                Toggle("Offload KV Cache to GPU", isOn: $settings.kvCacheOffload)
            }
            Toggle("Use mmap()", isOn: $settings.useMmap)
            HStack {
                Text("Seed")
                TextField("Random", text: Binding(
                    get: { settings.seed.map(String.init) ?? "" },
                    set: { newVal in
                        let digits = newVal.filter { $0.isNumber }
                        if let val = Int(digits) { settings.seed = val } else { settings.seed = nil }
                    }
                ))
                .platformKeyboardType(.numberPad)
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

    @ViewBuilder
    private func moeSettings(for info: MoEInfo) -> some View {
        if info.isMoE {
            let totalExperts = max(1, info.expertCount)
            let recommendedValue = info.defaultUsed.map { max(1, min(totalExperts, $0)) }
            let fallbackRecommendation = fallbackActiveExperts(for: info)
            let fallbackLabel = fallbackRecommendation == 1
            ? String(localized: "1 expert")
            : String.localizedStringWithFormat(String(localized: "%@ experts"), "\(fallbackRecommendation)")
            let currentValue: Int = {
                if allowsMoEExpertSelection {
                    return resolvedActiveExperts(for: info)
                }
                if let recommendedValue { return recommendedValue }
                return fallbackRecommendation
            }()
            VStack(alignment: .leading, spacing: 8) {
                if let moeLayers = info.moeLayerCount, let totalLayers = info.totalLayerCount {
                    Text("MoE layers: \(moeLayers) / \(totalLayers)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if totalExperts > 1, allowsMoEExpertSelection {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Experts Per Token")
                            .font(.subheadline.weight(.semibold))
                        Slider(
                            value: Binding<Double>(
                                get: { Double(resolvedActiveExperts(for: info)) },
                                set: { newValue in
                                    let resolved = min(max(1, Int(newValue.rounded())), totalExperts)
                                    settings.moeActiveExperts = resolved
                                }
                            ),
                            in: 1...Double(totalExperts),
                            step: 1
                        )
                    }
                }
                Text("Active experts per token: \(currentValue) of \(totalExperts)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if totalExperts > 1 {
                    if allowsMoEExpertSelection {
                        Text("Selecting more experts keeps additional expert weights resident in RAM and increases memory usage.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("MLX currently manages expert routing automatically; manual selection is not supported.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Only one expert is available for this model; the active expert count is fixed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let recommendedValue {
                    let recommendedLabel = recommendedValue == 1
                    ? String(localized: "1 expert")
                    : String.localizedStringWithFormat(String(localized: "%@ experts"), "\(recommendedValue)")
                    Text("Vendor recommendation: \(recommendedLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if allowsMoEExpertSelection, currentValue > recommendedValue {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Using more than \(recommendedLabel) significantly increases RAM usage.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Default selection (~\(fallbackLabel)) balances RAM usage against model quality.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var samplingSection: some View {
        Section(LocalizedStringKey("Sampling")) {
            samplingSectionContent
        }
    }

    @ViewBuilder
    private var samplingSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("Temperature"))
                    .font(.subheadline.weight(.semibold))
                Slider(value: $settings.temperature, in: 0...2, step: 0.05)
            }
            HStack {
                Text(String(format: "%.2f", settings.temperature))
                    .font(.footnote.monospacedDigit())
                Spacer()
                Text(LocalizedStringKey("Low = focused. High = varied."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("Top-p"))
                    .font(.subheadline.weight(.semibold))
                Slider(value: $settings.topP, in: 0...1, step: 0.01)
            }
            Text(String(format: "%.2f", settings.topP))
                .font(.footnote.monospacedDigit())
        }

        Stepper(value: $settings.topK, in: 1...2048, step: 1) {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "Top-k: %@"),
                    NumberFormatter.localizedString(from: NSNumber(value: settings.topK), number: .decimal)
                )
            )
        }

#if os(macOS)
        if supportsMinP {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("Min-p"))
                        .font(.subheadline.weight(.semibold))
                    Slider(value: $settings.minP, in: 0...1, step: 0.01)
                }
                Text(String(format: "%.2f", settings.minP))
                    .font(.footnote.monospacedDigit())
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            Stepper(
                value: Binding(
                    get: { Double(settings.repetitionPenalty) },
                    set: { settings.repetitionPenalty = Float($0) }
                ),
                in: 0.8...2.0,
                step: 0.05
            ) {
                let formatted = String(format: "%.2f", Double(settings.repetitionPenalty))
                Text(String.localizedStringWithFormat(String(localized: "Repetition penalty: %@"), formatted))
            }
            Stepper(value: $settings.repeatLastN, in: 0...4096, step: 16) {
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "Repeat last N tokens: %@"),
                        NumberFormatter.localizedString(from: NSNumber(value: settings.repeatLastN), number: .decimal)
                    )
                )
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
                    let formatted = String(format: "%.1f", Double(settings.presencePenalty))
                    Text(String.localizedStringWithFormat(String(localized: "Presence penalty: %@"), formatted))
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
                    let formatted = String(format: "%.1f", Double(settings.frequencyPenalty))
                    Text(String.localizedStringWithFormat(String(localized: "Frequency penalty: %@"), formatted))
                }
            }
            Text(LocalizedStringKey("Smooth loops and repeated phrases by tuning repetition controls."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
#endif
    }

#if os(macOS)
    @ViewBuilder
    private var speculativeDecodingSection: some View {
        Section("Speculative Decoding") {
            speculativeDecodingContent
        }
    }

    @ViewBuilder
    private var speculativeDecodingContent: some View {
        Text("Speed up with a smaller helper model.")
            .font(.caption)
            .foregroundStyle(.secondary)

        let options = speculativeDraftCandidates

        Picker("Helper Model", selection: Binding(
            get: { settings.speculativeDecoding.helperModelID },
            set: { settings.speculativeDecoding.helperModelID = $0 }
        )) {
            Text("None").tag(String?.none)
            ForEach(options, id: \.id) { candidate in
                Text(candidate.name).tag(String?.some(candidate.id))
            }
        }

        if settings.speculativeDecoding.helperModelID == nil {
            if options.isEmpty {
                Text("Install another model with the same architecture and equal or smaller size to enable speculative decoding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
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

    private var speculativeDraftCandidates: [LocalModel] {
        let base = resolvedModel
        return modelManager.downloadedModels.filter { candidate in
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
#endif

    @ViewBuilder
    private var mlxSettings: some View {
        Section("MLX") {
            mlxSettingsContent
        }
    }

    @ViewBuilder
    private var mlxSettingsContent: some View {
        Text("GPU off-load is not supported for this model.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if let moeInfo = resolvedMoEInfo {
            moeSettings(for: moeInfo)
        }
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
                .platformKeyboardType(.numberPad)
            }
            TextField("Tokenizer Path (tokenizer.json)", text: Binding(
                get: { settings.tokenizerPath ?? "" },
                set: { settings.tokenizerPath = $0.isEmpty ? nil : $0 }
            ))
            .platformAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.caption)
        }
    }

    @ViewBuilder
    private var benchmarkSection: some View {
        Section("Benchmark") {
            benchmarkSectionContent
        }
    }

    @ViewBuilder
    private var benchmarkSectionContent: some View {
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
        result.promptRate > 0 ? String.localizedStringWithFormat(String(localized: "%.1f tok/s"), result.promptRate) : "--"
    }

    private var generationRateText: String {
        result.generationRate > 0 ? String.localizedStringWithFormat(String(localized: "%.1f tok/s"), result.generationRate) : "--"
    }

    private var totalTimeText: String {
        String.localizedStringWithFormat(String(localized: "%.1fs"), result.totalDuration)
    }

    private var timeToFirstText: String {
        String.localizedStringWithFormat(String(localized: "%.2fs"), result.timeToFirstToken)
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
            let onText = String(localized: "On")
            let offText = String(localized: "Off")
            let gpuText = String(localized: "GPU")
            let cpuText = String(localized: "CPU")
            var badges: [OptimizationDescriptor] = []
            badges.append(OptimizationDescriptor(id: "flash", title: String(localized: "Flash Attention"), value: settings.flashAttention ? onText : offText, icon: "bolt.fill", isActive: settings.flashAttention))
            badges.append(OptimizationDescriptor(id: "kcache", title: String(localized: "K Cache"), value: settings.kCacheQuant.rawValue, icon: "memorychip", isActive: settings.kCacheQuant != .f16))
            if settings.flashAttention {
                badges.append(OptimizationDescriptor(id: "vcache", title: String(localized: "V Cache"), value: settings.vCacheQuant.rawValue, icon: "waveform.path.ecg", isActive: settings.vCacheQuant != .f16))
            }
            badges.append(OptimizationDescriptor(id: "kvoffload", title: String(localized: "KV Offload"), value: result.kvCacheOffloadActive ? gpuText : cpuText, icon: "externaldrive.connected.to.line.below", isActive: result.kvCacheOffloadActive))
            return badges
        case .mlx, .slm, .apple:
            return []
        }
    }

    @ViewBuilder
    private var optimizationSection: some View {
        Text(String(localized: "Optimizations in use"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        if optimizationBadges.isEmpty {
            Text(format == .slm
                 ? String(localized: "Leap SLM models manage runtime optimizations automatically.")
                 : String(localized: "This format doesn't expose tunable runtime optimizations."))
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

            // Hide optimization details entirely for MLX benchmarks.
            if format != .mlx {
                VStack(alignment: .leading, spacing: 8) {
                    optimizationSection
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    MetricTile(title: String(localized: "Token processing"), value: promptRateText)
                    MetricTile(title: String(localized: "Token generation"), value: generationRateText)
                }
                GridRow {
                    MetricTile(title: String(localized: "Total time"), value: totalTimeText)
                    MetricTile(title: String(localized: "First token"), value: timeToFirstText)
                }
                GridRow {
                    MetricTile(title: String(localized: "Peak memory"), value: memoryValueText, detail: memoryDeltaText)
                    MetricTile(title: String(localized: "Output tokens"), value: "\(result.generationTokens)")
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
    private let allowedSteps: Set<GuidedWalkthroughManager.Step> = [.modelSettingsIntro, .modelSettingsContext]
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
        case .modelSettingsContext:
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
            layerCount: layerHint,
            moeInfo: effectiveMoEInfo
        )
    }

    func runBenchmark() {
        guard !benchmarking, model.format != .apple else { return }
#if canImport(UIKit) && !os(visionOS)
        Haptics.impact(.light)
#endif
        let currentSettings = settings
        benchmarkError = nil
        benchmarking = true
        benchmarkProgress = 0
        benchmarkProgressDetail = String(localized: "Benchmark running…")

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
        Haptics.impact(.light)
#endif
        benchmarkTask?.cancel()
        benchmarkTask = nil
        benchmarkTaskID = nil
        benchmarking = false
        vm.loadingProgressTracker.completeLoading()
        benchmarkProgress = 0
        benchmarkProgressDetail = String(localized: "Benchmark running…")
    }

    func close() {
#if os(macOS)
        macModalDismiss()
#else
        dismiss()
#endif
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

#if os(macOS)
private extension View {
    func settingsWarningBackground() -> some View {
        self
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.yellow.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
            )
    }
}
#else
private extension View {
    func settingsWarningBackground() -> some View {
        self.listRowBackground(Color.yellow.opacity(0.1))
    }
}
#endif
