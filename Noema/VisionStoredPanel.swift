#if os(visionOS)
import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct VisionStoredPanel: View {
    @EnvironmentObject private var vm: ChatVM
    @EnvironmentObject private var modelManager: AppModelManager
    @EnvironmentObject private var datasetManager: DatasetManager
    @EnvironmentObject private var tabRouter: TabRouter
    @EnvironmentObject private var walkthrough: GuidedWalkthroughManager
    @AppStorage("offGrid") private var offGrid = false
    @AppStorage("hideGGUFOffloadWarning") private var hideGGUFOffloadWarning = false

    @State private var loadingModelID: LocalModel.ID?
    @State private var selectedModel: LocalModel?
    @State private var selectedDataset: LocalDataset?
    @State private var selectedRemoteID: IdentifiableBackendID?
    @State private var showRemoteBackendForm = false
    @State private var showImporter = false
    @State private var pendingPickedURLs: [URL] = []
    @State private var showNameSheet = false
    @State private var datasetName: String = ""
    @State private var importedDataset: LocalDataset?
    @State private var askStartIndexing = false
    @State private var datasetToIndex: LocalDataset?
    @State private var showOffloadWarning = false
    @State private var pendingLoad: (LocalModel, ModelSettings)?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    modelsSection
                    if !modelManager.remoteBackends.isEmpty {
                        remoteSection
                    }
                    if !modelManager.downloadedDatasets.isEmpty {
                        datasetsSection
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onAppear {
            modelManager.refresh()
            modelManager.refreshRemoteBackends(offGrid: offGrid)
        }
        .onChange(of: offGrid) { _, newValue in
            if !newValue {
                modelManager.refreshRemoteBackends(offGrid: false)
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
        .sheet(item: $selectedRemoteID) { backendID in
            NavigationStack {
                RemoteBackendDetailView(backendID: backendID.id)
                    .environmentObject(modelManager)
                    .environmentObject(vm)
                    .environmentObject(tabRouter)
            }
        }
        .sheet(isPresented: $showRemoteBackendForm) {
            RemoteBackendFormView { draft in
                try await modelManager.addRemoteBackend(from: draft)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library")
                    .font(.title2.weight(.semibold))
                Text(summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    showRemoteBackendForm = true
                } label: {
                    Label("Remote", systemImage: "antenna.radiowaves.left.and.right")
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("+ Add remote endpoint")

                Button {
                    showImporter = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Import Dataset")
            }
        }
    }

    private var summaryText: String {
        let models = modelManager.downloadedModels.count
        let datasets = modelManager.downloadedDatasets.count
        let remotes = modelManager.remoteBackends.count
        return "\(models) models • \(datasets) datasets • \(remotes) remotes"
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Models")
                .font(.headline)
            if modelManager.downloadedModels.isEmpty {
                emptyLibraryPrompt
            } else {
                VStack(spacing: 12) {
                    ForEach(modelManager.downloadedModels, id: \.id) { model in
                        modelCard(for: model)
                    }
                }
            }
        }
    }

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remote Endpoints")
                .font(.headline)
            VStack(spacing: 12) {
                ForEach(modelManager.remoteBackends, id: \.id) { backend in
                    remoteCard(for: backend)
                }
            }
        }
    }

    private var datasetsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Datasets")
                .font(.headline)
            VStack(spacing: 12) {
                ForEach(modelManager.downloadedDatasets) { dataset in
                    datasetCard(for: dataset)
                }
            }
        }
    }

    private var emptyLibraryPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No models yet")
                .font(.subheadline.weight(.semibold))
            Text("Download a model from Explore or add a remote endpoint to get started.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut) {
                        tabRouter.selection = .explore
                    }
                } label: {
                    Label("Explore", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showRemoteBackendForm = true
                } label: {
                    Label("Remote", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.6))
        )
    }

    private func modelCard(for model: LocalModel) -> some View {
        let isActive = modelManager.loadedModel?.id == model.id
        let isLoading = loadingModelID == model.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline.weight(.semibold))
                    Text("\(model.format.rawValue.uppercased()) • \(model.quant)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                } else if isLoading {
                    ProgressView()
                }
            }

            HStack(spacing: 12) {
                Button {
                    if isActive {
                        Task { await vm.unload() }
                    } else {
                        load(model)
                    }
                } label: {
                    Label(isActive ? "Unload" : "Load", systemImage: isActive ? "eject" : "play.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .orange : .accentColor)
                .disabled(isLoading)

                Button {
                    selectedModel = model
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.55))
        )
    }

    private func remoteCard(for backend: RemoteBackend) -> some View {
        Button {
            selectedRemoteID = IdentifiableBackendID(id: backend.id)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(backend.name)
                        .font(.subheadline.weight(.semibold))
                    Text(backend.baseURLString.isEmpty ? backend.endpointType.displayName : backend.baseURLString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if offGrid {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.orange)
                } else if modelManager.remoteBackendsFetching.contains(backend.id) {
                    ProgressView()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.55))
            )
        }
        .buttonStyle(.plain)
    }

    private func datasetCard(for dataset: LocalDataset) -> some View {
        Button {
            selectedDataset = dataset
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dataset.name)
                        .font(.subheadline.weight(.semibold))
                    Text(datasetSizeLabel(for: dataset))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if datasetManager.indexingDatasetID == dataset.datasetID {
                    ProgressView()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.55))
            )
        }
        .buttonStyle(.plain)
    }

    private func datasetSizeLabel(for dataset: LocalDataset) -> String {
        if dataset.sizeMB >= 1024 {
            let gb = dataset.sizeMB / 1024
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.0f MB", dataset.sizeMB)
        }
    }

    private func allowedUTTypes() -> [UTType] {
        var types: [UTType] = [.pdf, .plainText, .rtf, .html, .epub, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
    }

    private func allowedExtensions() -> Set<String> {
        ["pdf", "txt", "rtf", "html", "htm", "epub", "csv", "md"]
    }

    private func suggestName(from urls: [URL]) -> String? {
        guard let first = urls.first else { return nil }
        let base = first.deletingPathExtension().lastPathComponent
        return base.isEmpty ? nil : base
    }

    private func performImport() async {
        showNameSheet = false
        let name = datasetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let dataset = await datasetManager.importDocuments(from: pendingPickedURLs, suggestedName: name)
        if let dataset {
            importedDataset = dataset
            pendingPickedURLs = []
            datasetName = ""
            datasetToIndex = dataset
            askStartIndexing = true
        }
    }

    private struct IdentifiableBackendID: Identifiable {
        let id: RemoteBackend.ID
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
                if !ModelRAMAdvisor.fitsInRAM(format: model.format, sizeBytes: sizeBytes, contextLength: ctx, layerCount: layerHint) {
                    vm.loadError = "Model likely exceeds memory budget. Lower context size or use a smaller quant/model."
                    loadingModelID = nil
                    return
                }
            }

            UserDefaults.standard.set(true, forKey: "bypassRAMLoadPending")
            var loadURL = model.url
            switch model.format {
            case .gguf:
                loadURL = resolveGGUFURL(from: loadURL, model: model)
                if loadURL == model.url && !FileManager.default.fileExists(atPath: loadURL.path) {
                    loadingModelID = nil
                    return
                }
            case .mlx:
                loadURL = resolveMLXURL(from: loadURL, model: model)
            case .slm, .apple:
                break
            }

            let success = await vm.load(url: loadURL, settings: settings, format: model.format)
            if success {
                modelManager.updateSettings(settings, for: model)
                modelManager.markModelUsed(model)
            } else {
                modelManager.loadedModel = nil
            }
            loadingModelID = nil
            UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
        }
    }

    private func resolveGGUFURL(from url: URL, model: LocalModel) -> URL {
        var loadURL = url
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                if let file = try? FileManager.default.contentsOfDirectory(at: loadURL, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                    loadURL = file
                }
            } else if loadURL.pathExtension.lowercased() != "gguf" {
                if let alt = try? FileManager.default.contentsOfDirectory(at: loadURL.deletingLastPathComponent(), includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                    loadURL = alt
                }
            }
        } else {
            if let alt = InstalledModelsStore.firstGGUF(in: InstalledModelsStore.baseDir(for: .gguf, modelID: model.modelID)) {
                loadURL = alt
            }
        }
        return loadURL
    }

    private func resolveMLXURL(from url: URL, model: LocalModel) -> URL {
        var loadURL = url
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: loadURL.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                loadURL = loadURL.deletingLastPathComponent()
            }
        } else {
            loadURL = InstalledModelsStore.baseDir(for: .mlx, modelID: model.modelID)
        }
        return loadURL
    }
}
#endif
