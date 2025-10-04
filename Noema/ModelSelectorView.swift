// ModelSelectorView.swift
import SwiftUI
import UIKit
#if canImport(LeapSDK)
import LeapSDK
#endif

// Represents a locally available language model
struct LocalModel: Identifiable, Hashable {
    // Use a stable identifier to avoid List diffing glitches during refresh
    var id: String { url.path }
    let modelID: String
    let name: String
    /// Path to the model file on disk
    let url: URL
    let quant: String
    let architecture: String
    let format: ModelFormat
    let sizeGB: Double
    var isMultimodal: Bool
    var isToolCapable: Bool
    /// Whether the model is actually downloaded and available locally
    let isDownloaded: Bool
    let downloadDate: Date
    /// Last time this model was loaded
    var lastUsedDate: Date?
    var isFavourite: Bool = false
    var totalLayers: Int
}


struct ModelSelectorView: View {
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var tabRouter: TabRouter
    @EnvironmentObject var datasetManager: DatasetManager
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false
    @State private var selectedModel: LocalModel?
    @State private var showLoadProgress = false
    @State private var progress: CGFloat = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Group {
                    if let loaded = modelManager.loadedModel {
                        HStack {
                            Text(loaded.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(uiColor: .systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: UIConstants.extraLargeCornerRadius)
                                        .stroke(Color(uiColor: .systemGray3), lineWidth: 1)
                                )
                                .overlay(alignment: .bottom) {
                                    if showLoadProgress {
                                        GeometryReader { geo in
                                            Rectangle()
                                                .fill(Color.blue)
                                                .frame(width: geo.size.width * progress, height: 2)
                                        }
                                        .frame(height: 2)
                                        .transition(.opacity)
                                        .padding(.horizontal, 4)
                                    }
                                }
                                .cornerRadius(UIConstants.extraLargeCornerRadius)
                            Button(action: {
#if canImport(UIKit) && !os(visionOS)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
                                modelManager.loadedModel = nil
                                Task { await vm.unload() }
                            }) {
                                Image(systemName: "eject")
                            }
                            .buttonStyle(.bordered)
                        }
                        .transition(.opacity)
                    } else {
                        HStack {
                            Text("No model loaded")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(uiColor: .systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: UIConstants.extraLargeCornerRadius)
                                        .stroke(Color(uiColor: .systemGray3), lineWidth: 1)
                                )
                                .cornerRadius(UIConstants.extraLargeCornerRadius)
                        }
                        .transition(.opacity)
                    }

                }
                .padding(.horizontal)
                .animation(.easeInOut, value: modelManager.loadedModel)
                .onChange(of: vm.loading) { _, loading in
                    if loading {
                        startProgressAnimation()
                    } else {
                        finishProgressAnimation()
                    }
                }
                ModelListView(selectedModel: $selectedModel)
                    .environmentObject(vm)
                    .environmentObject(modelManager)
                    .environmentObject(tabRouter)
                    .environmentObject(datasetManager)
                Picker("Mode", selection: $isAdvancedMode) {
                    Text("Simple").tag(false)
                    Text("Advanced").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("My Models")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert(item: $datasetManager.embedAlert) { info in
            Alert(title: Text(info.message))
        }
    }

    @State private var timer: Timer?

    @MainActor
    private func startProgressAnimation() {
        timer?.invalidate()
        showLoadProgress = true
        progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                if progress < 0.9 { progress += 0.02 }
            }
        }
    }

    @MainActor
    private func finishProgressAnimation() {
        timer?.invalidate()
        progress = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) { showLoadProgress = false }
            progress = 0
        }
    }
}

struct ModelListView: View {
    @Binding var selectedModel: LocalModel?
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var tabRouter: TabRouter
    @EnvironmentObject var datasetManager: DatasetManager

    @State private var sort: SortOption = .recent
    @State private var manualParams = false
    @State private var showInfo = false
    @State private var detailModel: LocalModel?
    @State private var models: [LocalModel] = []
    @State private var loadingModelID: LocalModel.ID?
    @State private var showOffloadWarning = false
    @State private var pendingLoad: (LocalModel, ModelSettings)?
    @AppStorage("hideGGUFOffloadWarning") private var hideGGUFOffloadWarning = false

    enum SortOption: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case size = "Size"

        var id: String { rawValue }
    }

    var body: some View {
        List {
            Picker("Sort", selection: $sort) {
                ForEach(SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            Section(header: Text("Your Models")) {
                ForEach(sortedModels, id: \.id) { model in
                    let row = ModelRow(
                        model: model,
                        isLoading: loadingModelID == model.id
                    ) {
                        if manualParams {
                            selectedModel = model
                        } else {
                            var s = modelManager.settings(for: model)
                            // Default to "all layers" for GGUF if unset
                            if model.format == .gguf && s.gpuLayers == 0 {
                                s.gpuLayers = -1
                            }
                            startLoad(for: model, settings: s)
                        }
                    }
                    row
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedModel = model
                        }
                }
            }

            Section(header: Text("Your Datasets")) {
                ForEach(modelManager.downloadedDatasets) { ds in
                    let disabledForSLM = vm.isSLMModel
                    let disabledForRemote = modelManager.activeRemoteSession != nil
                    let isDisabled = disabledForSLM || disabledForRemote
                    DatasetRow(dataset: ds, indexing: datasetManager.indexingDatasetID == ds.datasetID)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isDisabled else { return }
                            guard datasetManager.indexingDatasetID != ds.datasetID, ds.isIndexed else { return }
                            let isActive = modelManager.activeDataset?.datasetID == ds.datasetID
                            vm.setDatasetForActiveSession(isActive ? nil : ds)
                        }
                        .opacity(isDisabled ? 0.5 : 1.0)
                        .allowsHitTesting(!isDisabled)
                }
            }

            Section {
                HStack {
                    Toggle("Manually choose model load parameters", isOn: $manualParams)
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .onAppear { modelManager.refresh(); models = modelManager.downloadedModels }
        .onReceive(modelManager.$downloadedModels) { models = $0 }
        .alert("Model Load Parameters", isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("When enabled, you will be asked to choose parameters every time a model loads.")
        }
        .sheet(item: $selectedModel) { model in
            ModelSettingsView(model: model) { settings in
                startLoad(for: model, settings: settings)
            }
            .environmentObject(modelManager)
            .environmentObject(vm)
        }
        .alert("Load Failed", isPresented: Binding(get: { vm.loadError != nil }, set: { _ in vm.loadError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.loadError ?? "")
        }
        .confirmationDialog(
            "Model doesn't support GPU offload",
            isPresented: $showOffloadWarning,
            titleVisibility: .visible
        ) {
            Button("Load") {
                if let (model, settings) = pendingLoad {
                    startLoad(for: model, settings: settings, bypassWarning: true)
                    pendingLoad = nil
                }
            }
            Button("Don't show again") {
                hideGGUFOffloadWarning = true
                if let (model, settings) = pendingLoad {
                    startLoad(for: model, settings: settings, bypassWarning: true)
                    pendingLoad = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingLoad = nil
            }
        } message: {
            if DeviceGPUInfo.supportsGPUOffload {
                Text("This model doesn't support GPU offload and generation speed will be significantly slower. Consider switching to an MLX model.")
            } else {
                Text("This model doesn't support GPU offload and generation speed will be significantly slower. Fastest option on this device: use an SLM (Leap) model.")
            }
        }
        }

    /// Models that are downloaded
    var filteredModels: [LocalModel] {
        return models.filter { model in
            model.isDownloaded
        }
    }

    var sortedModels: [LocalModel] {
        switch sort {
        case .recent:
            return filteredModels.sorted {
                let d0 = $0.lastUsedDate ?? $0.downloadDate
                let d1 = $1.lastUsedDate ?? $1.downloadDate
                return d0 > d1
            }
        case .size:
            return filteredModels.sorted { $0.sizeGB < $1.sizeGB }
        }
    }

    @MainActor
    private func startLoad(for model: LocalModel, settings: ModelSettings, bypassWarning: Bool = false) {
        if model.format == .gguf && !DeviceGPUInfo.supportsGPUOffload && !hideGGUFOffloadWarning && !bypassWarning {
            pendingLoad = (model, settings)
            showOffloadWarning = true
            return
        }
        loadingModelID = model.id
        Task { @MainActor in
            if model.format == .slm {
#if canImport(LeapSDK)
                do {
                    LeapBundleDownloader.sanitizeBundleIfNeeded(at: model.url)
                    let runner = try await Leap.load(url: model.url)
                    vm.activate(runner: runner, url: model.url)
                    // Persist default settings for SLM so they are remembered
                    modelManager.updateSettings(ModelSettings.default(for: .slm), for: model)
                    modelManager.markModelUsed(model)
                    tabRouter.selection = .chat
                } catch {
                    vm.loadError = error.localizedDescription
                    modelManager.loadedModel = nil
                }
                loadingModelID = nil
#else
                vm.loadError = "SLM models are not supported on this platform."
                modelManager.loadedModel = nil
                loadingModelID = nil
#endif
            } else {
                // Unload current model before checking RAM so available memory is accurate
                await vm.unload()
                try? await Task.sleep(nanoseconds: 200_000_000)

                // RAM safety gate unless bypassed
                let bypass = UserDefaults.standard.bool(forKey: "bypassRAMCheck")
                if !bypass {
                    let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
                    let ctx = Int(settings.contextLength)
                    let layerHint: Int? = model.totalLayers > 0 ? model.totalLayers : nil
                    if !ModelRAMAdvisor.fitsInRAM(format: model.format, sizeBytes: sizeBytes, contextLength: ctx, layerCount: layerHint) {
                        vm.loadError = "Model likely exceeds memory budget. Lower context size or use a smaller quant/model."
                        loadingModelID = nil
                        return
                    }
                }
                // Mark pending so if the app crashes during load, we won't autoload on next launch
                UserDefaults.standard.set(true, forKey: "bypassRAMLoadPending")
                var loadURL = model.url
                switch model.format {
                case .gguf:
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir) {
                        if isDir.boolValue {
                            // Prefer a valid non-mmproj GGUF under the directory
                            if let f = InstalledModelsStore.firstGGUF(in: loadURL) {
                                loadURL = f
                            } else {
                                vm.loadError = "Model file missing (.gguf)"
                                modelManager.loadedModel = nil
                                loadingModelID = nil
                                return
                            }
                        } else if loadURL.pathExtension.lowercased() != "gguf" || !InstalledModelsStore.isValidGGUF(at: loadURL) {
                            // Fallback to a valid GGUF next to the provided file path
                            if let f = InstalledModelsStore.firstGGUF(in: loadURL.deletingLastPathComponent()) {
                                loadURL = f
                            } else {
                                vm.loadError = "Model file missing (.gguf)"
                                modelManager.loadedModel = nil
                                loadingModelID = nil
                                return
                            }
                        }
                    } else {
                        // Path no longer exists (e.g., new sandbox). Try to re-discover under canonical base dir.
                        if let alt = InstalledModelsStore.firstGGUF(in: InstalledModelsStore.baseDir(for: .gguf, modelID: model.modelID)) {
                            loadURL = alt
                        } else {
                            vm.loadError = "Model path missing"
                            modelManager.loadedModel = nil
                            loadingModelID = nil
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
                            vm.loadError = "Model path missing"
                            modelManager.loadedModel = nil
                            loadingModelID = nil
                            return
                        }
                    }
                case .slm:
                    break
                case .apple:
                    break
                }

#if DEBUG
                var dbgDir: ObjCBool = false
                let _ = FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &dbgDir)
                print("[ModelListView] load url \(loadURL.path) \(dbgDir.boolValue ? "dir" : "file")")
#endif

                var clamped = settings
                clamped.contextLength = max(1, clamped.contextLength)
                if model.format == .gguf && model.totalLayers > 0 {
                    if clamped.gpuLayers >= 0 {
                        clamped.gpuLayers = min(max(0, clamped.gpuLayers), model.totalLayers)
                    }
                }

                let success = await vm.load(url: loadURL,
                                            settings: clamped,
                                            format: model.format)
                if success {
                    // Persist settings used for this successful load
                    modelManager.updateSettings(clamped, for: model)
                    // Also ensure durable store updated immediately after load
                    ModelSettingsStore.save(settings: clamped, forModelID: model.modelID, quantLabel: model.quant)
                    modelManager.markModelUsed(model)
                    tabRouter.selection = .chat
                } else {
                    modelManager.loadedModel = nil
                    // Bubble error to a toast via loadError; UI already observes it
                }
                // Clear pending flag if we survived the load attempt
                UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
                loadingModelID = nil
            }
        }
    }
}

struct ModelRow: View {
    let model: LocalModel
    let isLoading: Bool
    var isLoaded: Bool = false
    let loadAction: () -> Void
    @EnvironmentObject var vm: ChatVM

    var body: some View {
        let displayName: String = {
            if model.quant.isEmpty {
                return model.name
            } else {
                return model.name
                    .replacingOccurrences(of: "-\(model.quant)", with: "")
                    .replacingOccurrences(of: ".\(model.quant)", with: "")
            }
        }()

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if model.isFavourite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    Text(displayName)
                        .fontWeight(.medium)
                    if model.isReasoningModel {
                        Image(systemName: "brain")
                            .foregroundColor(.purple)
                    }
                    if UIConstants.showMultimodalUI && model.isMultimodal {
                        Image(systemName: "eye")
                    }
                    if model.isToolCapable {
                        Image(systemName: "hammer")
                            .foregroundColor(.blue)
                    }
                }
                Text(model.modelID.split(separator: "/").first.map(String.init) ?? model.modelID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if model.format != .slm {
                        Text(QuantExtractor.shortLabel(from: model.quant, format: model.format))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    }
                    Text(model.format.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(model.format.tagGradient)
                        .clipShape(Capsule())
                        .foregroundColor(.white)
                }
            }
            Spacer()
            Text(String(format: "%.1f GB", model.sizeGB))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !isLoaded {
                Button(action: {
#if canImport(UIKit) && !os(visionOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
                    loadAction()
                }) {
                    if isLoading { ProgressView() } else { Text("Load") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || vm.loading)
            } else {
                Label("Loaded", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.name), size \(String(format: "%.1f", model.sizeGB)) gigabytes")
    }
}

struct ModelDetailView: View {
    let model: LocalModel
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showFavouriteLimitAlert = false

    var body: some View {
        List {
            Section(header: Text(model.name)) {
                Label(model.architecture, systemImage: "cpu")
                Label(model.format.rawValue, systemImage: "doc")
                if model.format != .slm {
                    Label("Quant: \(model.quant)", systemImage: "dial.max")
                }
                Label(String(format: "Size: %.1f GB", model.sizeGB), systemImage: "externaldrive")
            }
            Section("Actions") {
                Button("Delete") {
                    showDeleteConfirm = true
                }

                Button(model.isFavourite ? "Unmark Favorite" : "Mark as Favorite") {
                    if !modelManager.toggleFavourite(model) {
                        showFavouriteLimitAlert = true
                    }
                }
            }
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
        .alert("Favorite Limit Reached", isPresented: $showFavouriteLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can only favorite up to three models.")
        }
    }
}

extension LocalModel {
    static func loadInstalled(store: InstalledModelsStore) -> [LocalModel] {
        let favs = Set(UserDefaults.standard.array(forKey: "favouriteModels") as? [String] ?? [])
        return store.all().map { item in
            var layers = item.totalLayers
            if layers == 0 && item.format == .gguf {
                layers = ModelScanner.layerCount(for: item.url, format: .gguf)
                if layers > 0 {
                    store.updateLayers(modelID: item.modelID, quantLabel: item.quantLabel, layers: layers)
                }
            }
            let name: String
            if item.format == .slm {
                name = LeapCatalogService.name(for: item.modelID) ?? item.modelID
            } else if item.format == .mlx {
                name = Self.friendlyMLXName(for: item.modelID, quantLabel: item.quantLabel)
            } else {
                name = item.modelID.split(separator: "/").last.map(String.init) ?? item.modelID
            }
            let finalURL = item.url
            return LocalModel(
                modelID: item.modelID,
                name: name,
                url: finalURL,
                quant: item.quantLabel,
                architecture: item.modelID,
                format: item.format,
                sizeGB: Double(item.sizeBytes) / 1_073_741_824.0,
                isMultimodal: item.isMultimodal,
                isToolCapable: item.isToolCapable,
                isDownloaded: true,
                downloadDate: item.installDate,
                lastUsedDate: item.lastUsed,
                isFavourite: favs.contains(item.url.path),
                totalLayers: layers

            )
        }
    }

}

private extension LocalModel {
    static func friendlyMLXName(for modelID: String, quantLabel: String) -> String {
        let repo = InstalledModelsStore.normalizedRepoName(for: .mlx, modelID: modelID)
        let humanized = repo
            .replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=[A-Za-z])(?=[0-9])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=[0-9])(?=[A-Za-z])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quantLabel.isEmpty else { return humanized }
        return "\(humanized) (\(quantLabel))"
    }
}

extension Array where Element == LocalModel {
    /// Removes duplicate models based on their file URL while preserving order.
    func removingDuplicateURLs() -> [LocalModel] {
        var seen = Set<URL>()
        var result: [LocalModel] = []
        for m in self {
            if !seen.contains(m.url) {
                seen.insert(m.url)
                result.append(m)
            }
        }
        return result
    }
}

#Preview {
    ModelSelectorView()
}