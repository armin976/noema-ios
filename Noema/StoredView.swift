#if os(iOS) || os(visionOS) || os(macOS)
// StoredView.swift
import SwiftUI
#if canImport(LeapSDK)
import LeapSDK
#endif
import Foundation
import UniformTypeIdentifiers
import PDFKit

struct ModelRow: View {
    let model: LocalModel
    let isLoading: Bool
    var isLoaded: Bool = false
    var settingsAction: (() -> Void)? = nil
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if model.isFavourite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.yellow)
                    }
                    Text(displayName)
                        .font(FontTheme.body)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.text)
                    
                    if model.isReasoningModel {
                        Image(systemName: "brain")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                    }
                    if UIConstants.showMultimodalUI && model.isMultimodal {
                        Image(systemName: "eye")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    if model.isToolCapable {
                        Image(systemName: "hammer")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }
                
                Text(model.modelID.split(separator: "/").first.map(String.init) ?? model.modelID)
                    .font(FontTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                // Chips
                HStack(spacing: 8) {
                    if model.format != .slm {
                        chip(text: QuantExtractor.shortLabel(from: model.quant, format: model.format), color: .accentColor)
                        if !model.architectureFamily.isEmpty {
                            chip(text: model.architectureFamily.uppercased(), color: .secondary)
                        }
                        if let moeInfo = model.moeInfo {
                            let isMoE = moeInfo.isMoE
                            chip(text: isMoE ? "MoE" : "Dense", color: isMoE ? .orange : .gray)
                        } else {
                            chip(text: String(localized: "Checking…"), color: .secondary, isStroked: true)
                        }
                    }
                }
                .padding(.top, 4)

                // Format chip
                HStack {
                    Text(model.format.rawValue)
                        .font(FontTheme.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(model.format.tagGradient)
                        .clipShape(Capsule())
                        .foregroundColor(.white)
                    Spacer(minLength: 0)
                }
            }
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                Text(String(format: "%.1f GB", model.sizeGB))
                    .font(FontTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                
                if !isLoaded {
                    #if os(macOS)
                    HStack(spacing: 8) {
                        if let settingsAction {
                            Button(action: settingsAction) {
                                Image(systemName: "gearshape")
                                    .font(FontTheme.caption.weight(.semibold))
                            }
                            .buttonStyle(GlassButtonStyle())
                            .help(LocalizedStringKey("Model settings"))
                            .disabled(isLoading || vm.loading)
                        }
                        loadButton
                    }
                    #else
                    loadButton
                    #endif
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(LocalizedStringKey("Loaded"))
                    }
                    .font(FontTheme.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.name), size \(String(format: "%.1f", model.sizeGB)) gigabytes")
    }
    
    @ViewBuilder
    private var loadButton: some View {
        Button(action: {
            #if canImport(UIKit) && !os(visionOS)
            Haptics.impact(.medium)
            #endif
            loadAction()
        }) {
            if isLoading {
                ProgressView().scaleEffect(0.7)
            } else {
                Text(LocalizedStringKey("Load"))
                    .font(FontTheme.caption.weight(.semibold))
            }
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(isLoading || vm.loading)
    }

    @ViewBuilder
    private func chip(text: String, color: Color, isStroked: Bool = false) -> some View {
        Text(text)
            .font(FontTheme.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isStroked ? Color.clear : color.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.3), lineWidth: isStroked ? 1 : 0)
            )
            .foregroundStyle(color)
    }
}

#endif

#if os(iOS) || os(visionOS)

struct StoredView: View {
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var tabRouter: TabRouter
    @EnvironmentObject var walkthrough: GuidedWalkthroughManager
    @AppStorage("offGrid") private var offGrid = false

    @State private var loadingModelID: LocalModel.ID?
    @State private var selectedModel: LocalModel?
    @State private var selectedDataset: LocalDataset?
    @State private var showOffGridInfo = false
    // Import flow
    @State private var showImporter = false
    @State private var pendingPickedURLs: [URL] = []
    @State private var showNameSheet = false
    @State private var datasetName: String = ""
    @State private var importedDataset: LocalDataset?
    @State private var askStartIndexing = false
    @State private var datasetToIndex: LocalDataset?
    @State private var showOffloadWarning = false
    @State private var pendingLoad: (LocalModel, ModelSettings)?
    @AppStorage("hideGGUFOffloadWarning") private var hideGGUFOffloadWarning = false
    @State private var showRemoteBackendForm = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        modelsSection
                        if !modelManager.remoteBackends.isEmpty {
                            remoteBackendsSection
                        }
                        if !modelManager.downloadedDatasets.isEmpty {
                            datasetsSection
                        }
                    }
                    .padding(AppTheme.padding)
                }
                .background(AppTheme.windowBackground)
                .guideHighlight(.storedList)
                .navigationTitle(LocalizedStringKey("Stored"))
                .task {
                    await modelManager.refreshAsync()
                    modelManager.refreshRemoteBackends(offGrid: offGrid)
                }
                
                // Floating off-grid indicator
                if offGrid {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { showOffGridInfo = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "wifi.slash")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(LocalizedStringKey("Off-Grid"))
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.gradient)
                                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                                )
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: offGrid)
                }
            }
            .sheet(item: $selectedModel) { model in
                ModelSettingsView(model: model) { settings in
                    load(model, settings: settings)
                }
                .environmentObject(modelManager)
                .environmentObject(vm)
                .environmentObject(walkthrough)
            }
            .sheet(item: $selectedDataset) { ds in
                LocalDatasetDetailView(dataset: ds)
                    .environmentObject(modelManager)
                    .environmentObject(datasetManager)
                    .environmentObject(vm)
            }
            .sheet(item: $importedDataset) { ds in
                LocalDatasetDetailView(dataset: ds)
                    .environmentObject(modelManager)
                    .environmentObject(datasetManager)
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showRemoteBackendForm) {
                RemoteBackendFormView { draft in
                    try await modelManager.addRemoteBackend(from: draft)
                }
            }
            .alert(item: $datasetManager.embedAlert) { info in
                Alert(title: Text(info.message))
            }
            .alert(LocalizedStringKey("Off-Grid Mode Active"), isPresented: $showOffGridInfo) {
                Button(LocalizedStringKey("OK"), role: .cancel) { }
            } message: {
                Text(LocalizedStringKey("You're in Off-Grid mode. The Explore tab is hidden and all network features are disabled. You can only use downloaded models and datasets."))
            }
            .alert(LocalizedStringKey("Load Failed"), isPresented: Binding(get: { vm.loadError != nil }, set: { _ in vm.loadError = nil })) {
                Button(LocalizedStringKey("OK"), role: .cancel) {}
            } message: {
                Text(vm.loadError ?? "")
            }
            .confirmationDialog(
                Text(LocalizedStringKey("Model doesn't support GPU offload")),
                isPresented: $showOffloadWarning,
                titleVisibility: .visible
            ) {
                Button(LocalizedStringKey("Load")) {
                    if let (model, settings) = pendingLoad {
                        load(model, settings: settings, bypassWarning: true)
                        pendingLoad = nil
                    }
                }
                Button(LocalizedStringKey("Don't show again")) {
                    hideGGUFOffloadWarning = true
                    if let (model, settings) = pendingLoad {
                        load(model, settings: settings, bypassWarning: true)
                        pendingLoad = nil
                    }
                }
                Button(LocalizedStringKey("Cancel"), role: .cancel) {
                    pendingLoad = nil
                }
            } message: {
                if DeviceGPUInfo.supportsGPUOffload {
                    Text(LocalizedStringKey("This model doesn't support GPU offload and generation speed will be significantly slower. Consider switching to an MLX model."))
                } else {
                    Text(LocalizedStringKey("This model doesn't support GPU offload and generation speed will be significantly slower. Fastest option on this device: use an SLM (Leap) model."))
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: allowedUTTypes(),
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    let filtered = urls.filter { allowedExtensions().contains($0.pathExtension.lowercased()) }
                    guard !filtered.isEmpty else { return }
                    pendingPickedURLs = filtered
                    datasetName = suggestName(from: filtered) ?? String(localized: "Imported Dataset")
                    showNameSheet = true
                case .failure:
                    break
                }
            }
            .sheet(isPresented: $showNameSheet) {
                DatasetImportNamePromptView(
                    datasetName: $datasetName,
                    onCancel: { showNameSheet = false },
                    onImport: { await performImport() }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(Text(LocalizedStringKey("Start indexing now?")), isPresented: $askStartIndexing, titleVisibility: .visible) {
                Button(LocalizedStringKey("Start")) {
                    if let ds = datasetToIndex {
                        datasetManager.startIndexing(dataset: ds)
                    }
                }
                Button(LocalizedStringKey("Later"), role: .cancel) {}
            } message: {
                Text(LocalizedStringKey("We'll extract text and prepare embeddings. You can also start later from the dataset details."))
            }
        }
        .onReceive(walkthrough.$pendingModelSettingsID) { id in
            guard let id else { return }
            if let model = modelManager.downloadedModels.first(where: { $0.modelID == id }) {
                selectedModel = model
            }
            walkthrough.pendingModelSettingsID = nil
        }
        .onReceive(walkthrough.$shouldDismissModelSettings) { shouldDismiss in
            guard shouldDismiss else { return }
            selectedModel = nil
            DispatchQueue.main.async {
                walkthrough.shouldDismissModelSettings = false
            }
        }
        .onChangeCompat(of: offGrid) { _, newValue in
            if !newValue {
                modelManager.refreshRemoteBackends(offGrid: false)
            }
        }
    }

    @ViewBuilder private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey("Your Models"))
                    .font(FontTheme.heading)
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Button {
                    showRemoteBackendForm = true
                } label: {
                    Text(LocalizedStringKey("Add remote endpoint"))
                        .font(FontTheme.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(LocalizedStringKey("Add remote endpoint"))
            }

            if modelManager.downloadedModels.isEmpty {
                VStack(spacing: 16) {
                    Text(LocalizedStringKey("No models yet"))
                        .font(FontTheme.heading)
                        .foregroundStyle(AppTheme.text)
                    Text(LocalizedStringKey("Download a model from Explore or add a remote endpoint to get started."))
                        .font(FontTheme.body)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                    Button {
                        withAnimation(.easeInOut) {
                            tabRouter.selection = .explore
                        }
                    } label: {
                        Label(LocalizedStringKey("Explore Models"), systemImage: "sparkles")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        showRemoteBackendForm = true
                    } label: {
                        Label(LocalizedStringKey("Add remote endpoint"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    if modelManager.downloadedDatasets.isEmpty {
                        Button {
                            showImporter = true
                        } label: {
                            Label(LocalizedStringKey("Import Dataset"), systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
                .background(AppTheme.cardFill)
                .cornerRadius(AppTheme.cornerRadius)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(modelManager.downloadedModels, id: \.id) { model in
                        ModelRow(model: model,
                                isLoading: loadingModelID == model.id,
                                isLoaded: modelManager.loadedModel?.id == model.id) {
                            load(model)
                        }
                        .environmentObject(vm)
                        .padding(20)
                        .background(AppTheme.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                                .stroke(AppTheme.cardStroke, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Always open settings on tap, do not trigger row button's load unintentionally
                            selectedModel = model
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    if modelManager.loadedModel?.id == model.id {
                                        await vm.unload()
                                    }
                                    modelManager.delete(model)
                                }
                            } label: {
                                Label(LocalizedStringKey("Delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var remoteBackendsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(LocalizedStringKey("Remote Backends"))
                .font(FontTheme.heading)
                .foregroundStyle(AppTheme.text)
            
            LazyVStack(spacing: 16) {
                ForEach(modelManager.remoteBackends, id: \.id) { backend in
                    NavigationLink {
                        RemoteBackendDetailView(backendID: backend.id)
                            .environmentObject(modelManager)
                    } label: {
                        RemoteBackendRow(
                            backend: backend,
                            isFetching: modelManager.remoteBackendsFetching.contains(backend.id),
                            isOffline: offGrid,
                            activeSession: modelManager.activeRemoteSession
                        )
                        .padding(20)
                        .background(AppTheme.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                                .stroke(AppTheme.cardStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                         Button(role: .destructive) {
                             modelManager.deleteRemoteBackend(id: backend.id)
                         } label: {
                             Label(LocalizedStringKey("Delete"), systemImage: "trash")
                         }
                    }
                }
            }
        }
    }

    @ViewBuilder private var datasetsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(LocalizedStringKey("Your Datasets"))
                .font(FontTheme.heading)
                .foregroundStyle(AppTheme.text)
            
            LazyVStack(spacing: 16) {
                ForEach(modelManager.downloadedDatasets) { ds in
                    DatasetRow(dataset: ds, indexing: datasetManager.indexingDatasetID == ds.datasetID)
                        .padding(20)
                        .background(AppTheme.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                                .stroke(AppTheme.cardStroke, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDataset = ds }
                        .contextMenu {
                            Button(role: .destructive) {
                                try? datasetManager.delete(ds)
                            } label: {
                                Label(LocalizedStringKey("Delete"), systemImage: "trash")
                            }
                        }
                }
            }
        }
        .guideHighlight(.storedDatasets)
    }

    private func load(_ model: LocalModel, settings: ModelSettings? = nil, bypassWarning: Bool = false) {
        let resolvedSettings = settings ?? modelManager.settings(for: model)
        if model.format == .gguf && !DeviceGPUInfo.supportsGPUOffload && !hideGGUFOffloadWarning && !bypassWarning {
            pendingLoad = (model, resolvedSettings)
            showOffloadWarning = true
            return
        }
        loadingModelID = model.id
        Task { @MainActor in
            let settings = resolvedSettings
            // Unload any current model to get accurate RAM info
            await vm.unload()
            try? await Task.sleep(nanoseconds: 200_000_000)

            // RAM safety gate unless bypassed
            let bypass = UserDefaults.standard.bool(forKey: "bypassRAMCheck")
            if !bypass {
                let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
                let ctx = Int(settings.contextLength)
                let layerHint: Int? = model.totalLayers > 0 ? model.totalLayers : nil
            if !ModelRAMAdvisor.fitsInRAM(format: model.format, sizeBytes: sizeBytes, contextLength: ctx, layerCount: layerHint, moeInfo: model.moeInfo) {
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
                        if let f = try? FileManager.default.contentsOfDirectory(at: loadURL, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                            loadURL = f
                        } else if let sub = try? FileManager.default.contentsOfDirectory(at: loadURL, includingPropertiesForKeys: nil).first(where: { url in
                            var d: ObjCBool = false
                            return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue && ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" })) != nil)
                        }), let found = try? FileManager.default.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                            loadURL = found
                        } else {
                            loadingModelID = nil
                            return
                        }
                    } else if loadURL.pathExtension.lowercased() != "gguf" {
                        if let f = try? FileManager.default.contentsOfDirectory(at: loadURL.deletingLastPathComponent(), includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                            loadURL = f
                        }
                    }
                } else {
                    if let alt = InstalledModelsStore.firstGGUF(in: InstalledModelsStore.baseDir(for: .gguf, modelID: model.modelID)) {
                        loadURL = alt
                    } else {
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
                        loadingModelID = nil
                        return
                    }
                }
            case .slm:
                break
            case .apple:
                // Unsupported model format
                loadingModelID = nil
                return
            }
            let success = await vm.load(url: loadURL, settings: settings, format: model.format)
            if success {
                modelManager.markModelUsed(model)
                tabRouter.selection = .chat
            } else {
                modelManager.loadedModel = nil
            }
            // Clear pending flag if we survived the load attempt
            UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
            loadingModelID = nil
        }
    }

    // MARK: - Import helpers
    private func allowedExtensions() -> Set<String> { ["pdf", "epub", "txt"] }
    private func allowedUTTypes() -> [UTType] {
        var types: [UTType] = [.pdf, .plainText]
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        return types
    }
    private func suggestName(from urls: [URL]) -> String? {
        if let pdfURL = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
            if let doc = PDFDocument(url: pdfURL), let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
        }
        if let u = urls.first {
            return u.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
        }
        return nil
    }
    private func performImport() async {
        let name = datasetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pendingPickedURLs.isEmpty, !name.isEmpty else { return }
        if let ds = await datasetManager.importDocuments(from: pendingPickedURLs, suggestedName: name) {
            importedDataset = ds
            datasetToIndex = ds
            askStartIndexing = true
        }
        pendingPickedURLs.removeAll()
        showNameSheet = false
    }

}

#elseif os(macOS)

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import PDFKit

private enum StoredDatasetModal: Equatable {
    case selected
    case imported
    case namePrompt
}

struct StoredView: View {
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var tabRouter: TabRouter
    @EnvironmentObject var walkthrough: GuidedWalkthroughManager
    @EnvironmentObject var macModalPresenter: MacModalPresenter
    @AppStorage("offGrid") private var offGrid = false
    @AppStorage("hideGGUFOffloadWarning") private var hideGGUFOffloadWarning = false

    @State private var loadingModelID: LocalModel.ID?
    @State private var selectedModel: LocalModel?
    @State private var selectedDataset: LocalDataset?
    @State private var importedDataset: LocalDataset?
    @State private var selectedBackendID: RemoteBackend.ID?
    @State private var showOffGridInfo = false
    @State private var showImporter = false
    @State private var pendingPickedURLs: [URL] = []
    @State private var showNameSheet = false
    @State private var datasetName: String = ""
    @State private var datasetToIndex: LocalDataset?
    @State private var askStartIndexing = false
    @State private var showRemoteBackendForm = false
    @State private var showOffloadWarning = false
    @State private var pendingLoad: (LocalModel, ModelSettings)?
    @State private var activeDatasetModal: StoredDatasetModal?

    var body: some View {
        navigationContent
        .alert(item: $datasetManager.embedAlert) { info in
            Alert(title: Text(info.message))
        }
        .alert(LocalizedStringKey("Off-Grid Mode Active"), isPresented: $showOffGridInfo) {
            Button(LocalizedStringKey("OK"), role: .cancel) { }
        } message: {
            Text(LocalizedStringKey("You're in Off-Grid mode. The Explore tab is hidden and all network features are disabled. You can only use downloaded models and datasets."))
        }
        .alert(LocalizedStringKey("Load Failed"), isPresented: Binding(get: { vm.loadError != nil }, set: { _ in vm.loadError = nil })) {
            Button(LocalizedStringKey("OK"), role: .cancel) {}
        } message: {
            Text(vm.loadError ?? "")
        }
        .confirmationDialog(
            Text(LocalizedStringKey("Model doesn't support GPU offload")),
            isPresented: $showOffloadWarning,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey("Load")) {
                if let (model, settings) = pendingLoad {
                    load(model, settings: settings, bypassWarning: true)
                    pendingLoad = nil
                }
            }
            Button(LocalizedStringKey("Don't show again")) {
                hideGGUFOffloadWarning = true
                if let (model, settings) = pendingLoad {
                    load(model, settings: settings, bypassWarning: true)
                    pendingLoad = nil
                }
            }
            Button(LocalizedStringKey("Cancel"), role: .cancel) {
                pendingLoad = nil
            }
        } message: {
            if DeviceGPUInfo.supportsGPUOffload {
                Text(LocalizedStringKey("This model doesn't support GPU offload and generation speed will be significantly slower. Consider switching to an MLX model."))
            } else {
                Text(LocalizedStringKey("This model doesn't support GPU offload and generation speed will be significantly slower. Fastest option on this device: use an SLM (Leap) model."))
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: allowedUTTypes(),
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let filtered = urls.filter { allowedExtensions().contains($0.pathExtension.lowercased()) }
                guard !filtered.isEmpty else { return }
                pendingPickedURLs = filtered
                datasetName = suggestName(from: filtered) ?? String(localized: "Imported Dataset")
                showNameSheet = true
            case .failure:
                break
            }
        }
        .confirmationDialog(Text(LocalizedStringKey("Start indexing now?")), isPresented: $askStartIndexing, titleVisibility: .visible) {
            Button(LocalizedStringKey("Start")) {
                if let ds = datasetToIndex {
                    datasetManager.startIndexing(dataset: ds)
                }
            }
            Button(LocalizedStringKey("Later"), role: .cancel) { }
        } message: {
            Text(LocalizedStringKey("We'll extract text and prepare embeddings. You can also start later from the dataset details."))
        }
        .onReceive(walkthrough.$pendingModelSettingsID) { id in
            guard let id else { return }
            if let model = modelManager.downloadedModels.first(where: { $0.modelID == id }) {
                selectedModel = model
            }
            walkthrough.pendingModelSettingsID = nil
        }
        .onReceive(walkthrough.$shouldDismissModelSettings) { shouldDismiss in
            guard shouldDismiss else { return }
            selectedModel = nil
            DispatchQueue.main.async {
                walkthrough.shouldDismissModelSettings = false
            }
        }
        .onChange(of: offGrid) { newValue in
            if !newValue {
                modelManager.refreshRemoteBackends(offGrid: false)
            }
        }
        .onChangeCompat(of: selectedModel) { _, model in
            guard let model else { return }
            presentModelSettings(for: model)
        }
        .onChangeCompat(of: showRemoteBackendForm) { _, presenting in
            guard presenting else { return }
            presentRemoteBackendForm()
        }
        .onChangeCompat(of: selectedBackendID) { _, backendID in
            guard let backendID else { return }
            presentRemoteBackendDetail(id: backendID)
        }
        .onChangeCompat(of: selectedDataset) { _, dataset in
            guard let dataset else {
                if activeDatasetModal == .selected {
                    dismissDatasetModal()
                }
                return
            }
            presentDatasetDetail(dataset, context: .selected)
        }
        .onChangeCompat(of: importedDataset) { _, dataset in
            guard let dataset else {
                if activeDatasetModal == .imported {
                    dismissDatasetModal()
                }
                return
            }
            presentDatasetDetail(dataset, context: .imported)
        }
        .onChangeCompat(of: showNameSheet) { _, show in
            if show {
                presentDatasetNamePrompt()
            } else if activeDatasetModal == .namePrompt {
                dismissDatasetModal()
            }
        }
    }

    private var navigationContent: some View {
        NavigationStack {
            ZStack {
                storedList
                if offGrid {
                    offGridBadge
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: offGrid)
                }
            }
        }
    }

    private var storedList: some View {
        ScrollView {
            VStack(spacing: 32) {
                modelsSection
                remoteBackendsSection
                datasetsSection
            }
            .padding(UIConstants.widePadding)
        }
        .background(AppTheme.windowBackground)
        .guideHighlight(.storedList)
        .task {
            await modelManager.refreshAsync()
            modelManager.refreshRemoteBackends(offGrid: offGrid)
            datasetManager.reloadFromDisk()
        }
    }

    private var offGridBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { showOffGridInfo = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 16, weight: .semibold))
                        Text(LocalizedStringKey("Off-Grid"))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.orange.gradient)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func storedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(UIConstants.defaultPadding)
            .glassifyIfAvailable(in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .background(AppTheme.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
            // Removed shadow for better scroll performance on macOS
    }

    @ViewBuilder private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey("Your Models"))
                    .font(FontTheme.heading)
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Button {
                    showRemoteBackendForm = true
                } label: {
                    Text(LocalizedStringKey("Add remote endpoint"))
                        .font(FontTheme.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(LocalizedStringKey("Add remote endpoint"))
            }
            
            if modelManager.downloadedModels.isEmpty {
                VStack(spacing: 16) {
                    Text(LocalizedStringKey("No models yet"))
                        .font(FontTheme.heading)
                        .foregroundStyle(AppTheme.text)
                    Text(LocalizedStringKey("Download a model from Explore or add a remote endpoint to get started."))
                        .font(FontTheme.body)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                    Button {
                        withAnimation(.easeInOut) {
                            tabRouter.selection = .explore
                        }
                    } label: {
                        Label(LocalizedStringKey("Explore Models"), systemImage: "sparkles")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        showRemoteBackendForm = true
                    } label: {
                        Label(LocalizedStringKey("Add remote endpoint"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    if modelManager.downloadedDatasets.isEmpty {
                        Button {
                            showImporter = true
                        } label: {
                            Label(LocalizedStringKey("Import Dataset"), systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
                .glassifyIfAvailable(in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                .background(AppTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(modelManager.downloadedModels, id: \.id) { model in
                        storedCard {
                            ModelRow(
                                model: model,
                                isLoading: loadingModelID == model.id,
                                isLoaded: modelManager.loadedModel?.id == model.id,
                                settingsAction: { selectedModel = model }
                            ) {
                                load(model)
                            }
                        }
                        .environmentObject(vm)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedModel = model
                        }
                        .contextMenu {
                            Button(LocalizedStringKey("Open Settings")) {
                                selectedModel = model
                            }
                            Button(LocalizedStringKey("Delete"), role: .destructive) {
                                Task {
                                    if modelManager.loadedModel?.id == model.id {
                                        await vm.unload()
                                    }
                                    modelManager.delete(model)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var remoteBackendsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(LocalizedStringKey("Remote Backends"))
                .font(FontTheme.heading)
                .foregroundStyle(AppTheme.text)
            
            if modelManager.remoteBackends.isEmpty {
                VStack(spacing: 16) {
                    Text(LocalizedStringKey("No remote endpoints configured."))
                        .font(FontTheme.body)
                        .foregroundStyle(AppTheme.secondaryText)
                    Button {
                        showRemoteBackendForm = true
                    } label: {
                        Label(LocalizedStringKey("Add Remote Endpoint"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .glassifyIfAvailable(in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                .background(AppTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(modelManager.remoteBackends, id: \.id) { backend in
                        Button {
                            selectedBackendID = backend.id
                        } label: {
                            storedCard {
                                RemoteBackendRow(
                                    backend: backend,
                                    isFetching: modelManager.remoteBackendsFetching.contains(backend.id),
                                    isOffline: offGrid,
                                    activeSession: modelManager.activeRemoteSession
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(LocalizedStringKey("Delete"), role: .destructive) {
                                modelManager.deleteRemoteBackend(id: backend.id)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var datasetsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(LocalizedStringKey("Datasets"))
                    .font(FontTheme.heading)
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Text(LocalizedStringKey("Import Dataset"))
                        .font(FontTheme.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            
            if modelManager.downloadedDatasets.isEmpty {
                VStack(spacing: 16) {
                    Text(LocalizedStringKey("No datasets yet"))
                        .font(FontTheme.heading)
                        .foregroundStyle(AppTheme.text)
                    Text(LocalizedStringKey("Import PDFs, EPUBs, or text files to build local knowledge bases."))
                        .font(FontTheme.body)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                    Button {
                        showImporter = true
                    } label: {
                        Label(LocalizedStringKey("Import Dataset"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .glassifyIfAvailable(in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                .background(AppTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(modelManager.downloadedDatasets) { ds in
                        storedCard {
                            DatasetRow(dataset: ds, indexing: datasetManager.indexingDatasetID == ds.datasetID)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDataset = ds }
                        .contextMenu {
                            Button(LocalizedStringKey("Delete"), role: .destructive) {
                                try? datasetManager.delete(ds)
                            }
                        }
                    }
                }
            }
        }
        .guideHighlight(.storedDatasets)
    }

    private func load(_ model: LocalModel, settings: ModelSettings? = nil, bypassWarning: Bool = false) {
        let resolvedSettings = settings ?? modelManager.settings(for: model)
        if model.format == .gguf && !DeviceGPUInfo.supportsGPUOffload && !hideGGUFOffloadWarning && !bypassWarning {
            pendingLoad = (model, resolvedSettings)
            showOffloadWarning = true
            return
        }
        loadingModelID = model.id
        Task { @MainActor in
            let settings = resolvedSettings
            await vm.unload()
            try? await Task.sleep(nanoseconds: 200_000_000)

            let bypass = UserDefaults.standard.bool(forKey: "bypassRAMCheck")
            if !bypass {
                let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
                let ctx = Int(settings.contextLength)
                let layerHint: Int? = model.totalLayers > 0 ? model.totalLayers : nil
                if !ModelRAMAdvisor.fitsInRAM(format: model.format, sizeBytes: sizeBytes, contextLength: ctx, layerCount: layerHint, moeInfo: model.moeInfo) {
                    vm.loadError = String(localized: "Model likely exceeds memory budget. Lower context size or use a smaller quant/model.")
                    loadingModelID = nil
                    return
                }
            }

            UserDefaults.standard.set(true, forKey: "bypassRAMLoadPending")
            var loadURL = model.url
            switch model.format {
            case .gguf:
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        if let f = try? FileManager.default.contentsOfDirectory(at: loadURL, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                            loadURL = f
                        } else if let sub = try? FileManager.default.contentsOfDirectory(at: loadURL, includingPropertiesForKeys: nil).first(where: { url in
                            var d: ObjCBool = false
                            return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue && ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" })) != nil)
                        }), let found = try? FileManager.default.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                            loadURL = found
                        } else {
                            loadingModelID = nil
                            return
                        }
                    } else if loadURL.pathExtension.lowercased() != "gguf" {
                        if let f = try? FileManager.default.contentsOfDirectory(at: loadURL.deletingLastPathComponent(), includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                            loadURL = f
                        }
                    }
                } else {
                    if let alt = InstalledModelsStore.firstGGUF(in: InstalledModelsStore.baseDir(for: .gguf, modelID: model.modelID)) {
                        loadURL = alt
                    } else {
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
                        loadingModelID = nil
                        return
                    }
                }
            case .slm:
                break
            case .apple:
                loadingModelID = nil
                return
            }

            let success = await vm.load(url: loadURL, settings: settings, format: model.format)
            if success {
                modelManager.markModelUsed(model)
                tabRouter.selection = .chat
            } else {
                modelManager.loadedModel = nil
            }
            UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
            loadingModelID = nil
        }
    }

    private func allowedExtensions() -> Set<String> { ["pdf", "epub", "txt"] }

    private func allowedUTTypes() -> [UTType] {
        var types: [UTType] = [.pdf, .plainText]
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        return types
    }

    private func suggestName(from urls: [URL]) -> String? {
        if let pdfURL = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
            if let doc = PDFDocument(url: pdfURL), let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
        }
        if let u = urls.first {
            return u.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
        }
        return nil
    }

    private func performImport() async {
        let name = datasetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pendingPickedURLs.isEmpty, !name.isEmpty else { return }
        if let ds = await datasetManager.importDocuments(from: pendingPickedURLs, suggestedName: name) {
            importedDataset = ds
            datasetToIndex = ds
            askStartIndexing = true
        }
        pendingPickedURLs.removeAll()
        showNameSheet = false
    }

    private func presentDatasetDetail(_ dataset: LocalDataset, context: StoredDatasetModal) {
        activeDatasetModal = context
        macModalPresenter.present(
            title: dataset.name,
            subtitle: dataset.source.isEmpty ? nil : dataset.source,
            showCloseButton: false,
            dimensions: MacModalDimensions(
                minWidth: 600,
                idealWidth: 660,
                maxWidth: 760,
                minHeight: 560,
                idealHeight: 640,
                maxHeight: 780
            ),
            contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
            onDismiss: {
                let currentContext = context
                activeDatasetModal = nil
                switch currentContext {
                case .selected:
                    selectedDataset = nil
                case .imported:
                    importedDataset = nil
                case .namePrompt:
                    showNameSheet = false
                }
            }
        ) {
            LocalDatasetDetailView(dataset: dataset)
                .environmentObject(modelManager)
                .environmentObject(datasetManager)
                .environmentObject(vm)
        }
    }

    private func presentDatasetNamePrompt() {
        activeDatasetModal = .namePrompt
        macModalPresenter.present(
            title: String(localized: "Import Dataset"),
            subtitle: String(localized: "Name your dataset"),
            showCloseButton: true,
            dimensions: MacModalDimensions(
                minWidth: 360,
                idealWidth: 400,
                maxWidth: 460,
                minHeight: 220,
                idealHeight: 240,
                maxHeight: 320
            ),
            onDismiss: {
                activeDatasetModal = nil
                showNameSheet = false
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedStringKey("Name your dataset"))
                    .font(.headline)
                TextField(LocalizedStringKey("Dataset name"), text: $datasetName)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                HStack {
                    Button(LocalizedStringKey("Cancel")) { showNameSheet = false }
                    Spacer()
                    Button(LocalizedStringKey("Import")) { Task { await performImport() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(datasetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(minWidth: 320, minHeight: 200)
        }
    }

    private func dismissDatasetModal() {
        guard activeDatasetModal != nil else { return }
        activeDatasetModal = nil
        if macModalPresenter.isPresented {
            macModalPresenter.dismiss()
        }
    }

    private func presentModelSettings(for model: LocalModel) {
        macModalPresenter.present(
            title: model.name,
            subtitle: model.format.rawValue,
            showCloseButton: true,
            dimensions: MacModalDimensions(
                minWidth: 600,
                idealWidth: 660,
                maxWidth: 720,
                minHeight: 540,
                idealHeight: 620,
                maxHeight: 760
            ),
            contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
            onDismiss: { selectedModel = nil }
        ) {
            ModelSettingsView(model: model) { settings in
                load(model, settings: settings)
            }
            .environmentObject(modelManager)
            .environmentObject(vm)
            .environmentObject(walkthrough)
        }
    }

    private func presentRemoteBackendForm() {
        macModalPresenter.present(
            title: String(localized: "Custom Backend"),
            subtitle: String(localized: "Add a remote inference endpoint"),
            showCloseButton: false,
            dimensions: MacModalDimensions(
                minWidth: 560,
                idealWidth: 620,
                maxWidth: 720,
                minHeight: 560,
                idealHeight: 640,
                maxHeight: 780
            ),
            onDismiss: { showRemoteBackendForm = false }
        ) {
            RemoteBackendFormView { draft in
                try await modelManager.addRemoteBackend(from: draft)
            }
        }
    }

    private func presentRemoteBackendDetail(id backendID: RemoteBackend.ID) {
        macModalPresenter.present(
            title: modelManager.remoteBackend(withID: backendID)?.name,
            subtitle: String(localized: "Connection details"),
            showCloseButton: true,
            dimensions: MacModalDimensions(
                minWidth: 600,
                idealWidth: 660,
                maxWidth: 760,
                minHeight: 540,
                idealHeight: 620,
                maxHeight: 760
            ),
            contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
            onDismiss: { selectedBackendID = nil }
        ) {
            RemoteBackendDetailView(backendID: backendID)
                .environmentObject(modelManager)
                .environmentObject(vm)
                .environmentObject(tabRouter)
        }
    }

}

#endif
