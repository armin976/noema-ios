// StoredView.swift
import SwiftUI
import LeapSDK
import Foundation
import UniformTypeIdentifiers
import PDFKit

struct StoredView: View {
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var tabRouter: TabRouter
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

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    if !modelManager.downloadedModels.isEmpty {
                        modelsSection
                    }
                    if !modelManager.downloadedDatasets.isEmpty {
                        datasetsSection
                    }
                    if modelManager.downloadedModels.isEmpty && modelManager.downloadedDatasets.isEmpty {
                        VStack(spacing: 12) {
                            Text("No items yet")
                                .font(.headline)
                            Text("Import a dataset (PDF, EPUB, or TXT) from Files, or explore online.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                showImporter = true
                            } label: {
                                Label("Import Dataset", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                    }
                }
                // Avoid forcing List re-creation on every models refresh to prevent scroll glitches
                .navigationTitle("Stored")
                .onAppear { modelManager.refresh() }
                
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
                                    Text("Off-Grid")
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
            .alert(item: $datasetManager.embedAlert) { info in
                Alert(title: Text(info.message))
            }
            .alert("Off-Grid Mode Active", isPresented: $showOffGridInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You're in Off-Grid mode. The Explore tab is hidden and all network features are disabled. You can only use downloaded models and datasets.")
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
                        load(model, settings: settings, bypassWarning: true)
                        pendingLoad = nil
                    }
                }
                Button("Don't show again") {
                    hideGGUFOffloadWarning = true
                    if let (model, settings) = pendingLoad {
                        load(model, settings: settings, bypassWarning: true)
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
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: allowedUTTypes(),
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    let filtered = urls.filter { allowedExtensions().contains($0.pathExtension.lowercased()) }
                    guard !filtered.isEmpty else { return }
                    pendingPickedURLs = filtered
                    datasetName = suggestName(from: filtered) ?? "Imported Dataset"
                    showNameSheet = true
                case .failure:
                    break
                }
            }
            .sheet(isPresented: $showNameSheet) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Name your dataset")
                            .font(.headline)
                        TextField("Dataset name", text: $datasetName)
                            .textFieldStyle(.roundedBorder)
                        Spacer()
                        HStack {
                            Button("Cancel") { showNameSheet = false }
                            Spacer()
                            Button("Import") { Task { await performImport() } }
                                .buttonStyle(.borderedProminent)
                                .disabled(datasetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding()
                    .navigationTitle("Import Dataset")
                }
                .presentationDetents([.fraction(0.35)])
            }
            .confirmationDialog("Start indexing now?", isPresented: $askStartIndexing, titleVisibility: .visible) {
                Button("Start") {
                    if let ds = datasetToIndex {
                        datasetManager.startIndexing(dataset: ds)
                    }
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text("We'll extract text and prepare embeddings. You can also start later from the dataset details.")
            }
        }
    }

    @ViewBuilder private var modelsSection: some View {
        Section("Your Models") {
            ForEach(modelManager.downloadedModels, id: \.id) { model in
                ModelRow(model: model, 
                        isLoading: loadingModelID == model.id,
                        isLoaded: modelManager.loadedModel?.id == model.id) {
                    load(model)
                }
                .environmentObject(vm)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Always open settings on tap, do not trigger row button's load unintentionally
                    selectedModel = model
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task {
                            if modelManager.loadedModel?.id == model.id {
                                await vm.unload()
                            }
                            modelManager.delete(model)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder private var datasetsSection: some View {
        Section("Your Datasets") {
            ForEach(modelManager.downloadedDatasets) { ds in
                DatasetRow(dataset: ds, indexing: datasetManager.indexingDatasetID == ds.datasetID)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedDataset = ds }
                    .swipeActions {
                        Button(role: .destructive) {
                            try? datasetManager.delete(ds)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
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
