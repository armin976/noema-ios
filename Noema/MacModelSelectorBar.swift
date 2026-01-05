import SwiftUI
#if os(macOS)
import AppKit
#if canImport(LeapSDK)
import LeapSDK
#endif

private func performMediumImpact() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
}

/// Localized size formatter that respects the view's locale (ByteCountFormatter does not expose locale).
private func localizedByteCountString(bytes: Int64, locale: Locale) -> String {
    let useGB = bytes >= 1_073_741_824
    let value = useGB ? Double(bytes) / 1_073_741_824.0 : Double(bytes) / 1_048_576.0
    let unit: UnitInformationStorage = useGB ? .gigabytes : .megabytes

    let formatter = MeasurementFormatter()
    formatter.locale = locale
    formatter.unitOptions = .providedUnit
    formatter.unitStyle = .medium
    formatter.numberFormatter.locale = locale
    formatter.numberFormatter.maximumFractionDigits = 1
    formatter.numberFormatter.minimumFractionDigits = 0
    return formatter.string(from: Measurement(value: value, unit: unit))
}

struct MacModelSelectorBar: View {
    @EnvironmentObject private var chatVM: ChatVM
    @EnvironmentObject private var modelManager: AppModelManager
    @EnvironmentObject private var datasetManager: DatasetManager
    @EnvironmentObject private var tabRouter: TabRouter
    @EnvironmentObject private var macModalPresenter: MacModalPresenter
    @EnvironmentObject private var walkthrough: GuidedWalkthroughManager
    @EnvironmentObject private var macChatChrome: MacChatChromeState
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPicker = false
    @State private var showOffloadWarning = false
    @State private var pendingLoad: (LocalModel, ModelSettings)?
    @AppStorage("hideGGUFOffloadWarning") private var hideGGUFOffloadWarning = false
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false

    private let controlHeight: CGFloat = 32
    private let controlCornerRadius: CGFloat = 10

    private enum Status {
        case unloaded
        case loading
        case local(LocalModel)
        case remote(ActiveRemoteSession)
    }

    var body: some View {
        HStack(spacing: 8) {
            selectorButton
            if isAdvancedMode {
                advancedControlsButton
            }
            if case .local(let model) = status, !chatVM.loading {
                settingsButton(for: model)
                ejectButton {
                    performMediumImpact()
                    modelManager.loadedModel = nil
                    Task { await chatVM.unload() }
                }
            } else if case .remote = status {
                ejectButton {
                    performMediumImpact()
                    chatVM.deactivateRemoteSession()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("This model doesn't support GPU offload and may run slowly. Consider an MLX model.")
            } else {
                Text("This model doesn't support GPU offload and may run slowly. Fastest option: use an SLM model.")
            }
        }
    }

    private var advancedControlsButton: some View {
        Button {
            performMediumImpact()
            withAnimation(.easeInOut(duration: 0.2)) {
                macChatChrome.showAdvancedControls.toggle()
            }
        } label: {
            Image(systemName: "sidebar.trailing")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: controlHeight, height: controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                        .fill(macChatChrome.showAdvancedControls ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(macChatChrome.showAdvancedControls ? Color.accentColor : Color.primary)
        .help(
            macChatChrome.showAdvancedControls
            ? String(localized: "Hide advanced controls")
            : String(localized: "Show advanced controls")
        )
    }

    private var selectorButton: some View {
        let label = selectorLabel

        return Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(titleColor)
                VStack(alignment: .leading, spacing: label.subtitle == nil ? 0 : 2) {
                    Text(label.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = label.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(subtitleColor)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if chatVM.loading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(indicatorColor)
                }
            }
            .frame(height: controlHeight)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                    .fill(statusBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("l", modifiers: [.command])
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            MacModelPicker(
                isPresented: $showPicker,
                macModalPresenter: macModalPresenter
            )
            .environmentObject(chatVM)
            .environmentObject(modelManager)
            .environmentObject(datasetManager)
            .environmentObject(tabRouter)
            .environmentObject(walkthrough)
            .frame(minWidth: 520, maxWidth: 560, minHeight: 440, maxHeight: 620)
        }
    }

    private func ejectButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "eject")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: controlHeight, height: controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func settingsButton(for model: LocalModel) -> some View {
        Button {
            presentSettings(for: model)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: controlHeight, height: controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(String(localized: "Adjust model settings"))
    }

    private func presentSettings(for model: LocalModel) {
        macModalPresenter.present(
            title: model.name,
            subtitle: String(localized: "Model Settings"),
            showCloseButton: true,
            dimensions: .modelSettings,
            contentInsets: EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24)
        ) {
            ModelSettingsView(model: model) { settings in
                macModalPresenter.dismiss()
                startLoad(for: model, settings: settings)
            }
            .environmentObject(modelManager)
            .environmentObject(chatVM)
            .environmentObject(walkthrough)
        }
    }

    private var status: Status {
        if let remote = modelManager.activeRemoteSession {
            return .remote(remote)
        }
        if chatVM.loading {
            return .loading
        }
        if let loaded = modelManager.loadedModel {
            return .local(loaded)
        }
        return .unloaded
    }

    private var statusBackground: Color {
        switch status {
        case .remote:
            return Color.accentColor.opacity(0.25)
        case .local:
            return Color.green.opacity(0.18)
        case .loading:
            return Color.primary.opacity(0.12)
        case .unloaded:
            return Color.primary.opacity(0.08)
        }
    }

    private var titleColor: Color {
        switch status {
        case .remote:
            return Color.white
        case .local:
            return colorScheme == .dark ? Color.white : Color.black
        case .loading:
            return Color.primary
        case .unloaded:
            return Color.primary
        }
    }

    private var subtitleColor: Color {
        switch status {
        case .remote:
            return Color.white.opacity(0.8)
        case .local:
            return colorScheme == .dark
                ? Color.white.opacity(0.8)
                : Color.black.opacity(0.7)
        case .loading:
            return Color.secondary
        case .unloaded:
            return Color.secondary
        }
    }

    private var indicatorColor: Color {
        switch status {
        case .remote:
            return Color.white.opacity(0.9)
        case .local:
            return colorScheme == .dark
                ? Color.white.opacity(0.9)
                : Color.black.opacity(0.75)
        default:
            return Color.secondary.opacity(0.8)
        }
    }

    private var selectorLabel: (title: String, subtitle: String?) {
        switch status {
        case .local(let model):
            return (model.name, statusSubtitle)
        case .remote(let session):
            return (session.modelName, remoteSubtitle(for: session))
        case .loading:
            return (String(localized: "Loading model…"), statusSubtitle)
        case .unloaded:
            return (String(localized: "Select a model to load"), nil)
        }
    }

    private var statusSubtitle: String {
        if let dataset = modelManager.activeDataset, datasetManager.indexingDatasetID != dataset.datasetID {
            return String(localized: "Using \(dataset.name)")
        }
        if case .local(let model) = status {
            return subtitle(for: model)
        }
        if case .loading = status {
            return String(localized: "Please wait")
        }
        return String(localized: "Models Library")
    }

    private func subtitle(for model: LocalModel) -> String {
        var parts: [String] = []
        if model.format != .slm && !model.quant.isEmpty {
            parts.append(model.quant)
        }
        parts.append(model.format.rawValue.uppercased())
        let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
        parts.append(localizedByteCountString(bytes: sizeBytes, locale: locale))
        return parts.joined(separator: " · ")
    }

    private func remoteSubtitle(for session: ActiveRemoteSession) -> String {
        var parts: [String] = [session.backendName]
        parts.append(session.transport.label)
        if session.streamingEnabled {
            parts.append(String(localized: "Streaming"))
        }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func startLoad(for model: LocalModel, settings: ModelSettings, bypassWarning: Bool = false) {
        if model.format == .gguf && !DeviceGPUInfo.supportsGPUOffload && !hideGGUFOffloadWarning && !bypassWarning {
            pendingLoad = (model, settings)
            showOffloadWarning = true
            return
        }

        pendingLoad = nil

        Task { @MainActor in
            _ = await performModelLoad(
                model: model,
                settings: settings,
                chatVM: chatVM,
                modelManager: modelManager,
                tabRouter: tabRouter
            )
        }
    }
}

private struct MacModelPicker: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var chatVM: ChatVM
    @EnvironmentObject private var modelManager: AppModelManager
    @EnvironmentObject private var datasetManager: DatasetManager
    @EnvironmentObject private var tabRouter: TabRouter
    @EnvironmentObject private var walkthrough: GuidedWalkthroughManager
    @Environment(\.locale) private var locale
    let macModalPresenter: MacModalPresenter

    @State private var searchText = ""
    @State private var sort: SortOption = .recent
    @AppStorage("macManualModelParams") private var manualParams = false
    @State private var models: [LocalModel] = []
    @State private var loadingModelID: LocalModel.ID?
    @State private var pendingLoad: (LocalModel, ModelSettings)?
    @State private var showOffloadWarning = false
    @AppStorage("hideGGUFOffloadWarning") private var hideGGUFOffloadWarning = false

    enum SortOption: String, CaseIterable, Identifiable {
        case recent = "Recency"
        case size = "Size"
        case name = "Name"

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .recent: return LocalizedStringKey("Recency")
            case .size: return LocalizedStringKey("Size")
            case .name: return LocalizedStringKey("Name")
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            modelList
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            modelManager.refresh()
            models = modelManager.downloadedModels
        }
        .onReceive(modelManager.$downloadedModels) { models = $0 }
        .alert("Load Failed", isPresented: Binding(
            get: { chatVM.loadError != nil },
            set: { _ in chatVM.loadError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(chatVM.loadError ?? "")
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
                Text("This model doesn't support GPU offload and may run slowly. Consider an MLX model.")
            } else {
                Text("This model doesn't support GPU offload and may run slowly. Fastest option: use an SLM model.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            TextField(text: $searchText, prompt: Text("Type to filter models…")) {
                Text("Type to filter models…")
            }
            .textFieldStyle(.roundedBorder)
            HStack {
                Picker(selection: $sort) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.titleKey).tag(option)
                    }
                } label: {
                    Text("Sort")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Spacer()
                Button {
                    tabRouter.selection = .explore
                    UserDefaults.standard.set(ExploreSection.models.rawValue, forKey: "exploreSection")
                    isPresented = false
                } label: {
                    Label("Model Library", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.link)
            }
        }
    }

    private var modelList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(filteredModels, id: \.id) { model in
                    MacModelRow(
                        model: model,
                        isLoading: loadingModelID == model.id,
                        activeModelID: chatVM.loadedModelURL?.path == model.url.path ? model.id : nil,
                        manualParams: manualParams,
                        onSelect: {
                            if manualParams {
                                presentSettings(for: model)
                            } else {
                                let settings = modelManager.settings(for: model)
                                startLoad(for: model, settings: settings)
                            }
                        }
                    )
                }
                if filteredModels.isEmpty {
                    VStack(spacing: 6) {
                        Text("No models match your search.")
                            .font(.system(size: 13, weight: .semibold))
                        Button {
                            tabRouter.selection = .explore
                            UserDefaults.standard.set(ExploreSection.models.rawValue, forKey: "exploreSection")
                            isPresented = false
                        } label: {
                            Text("Browse Explore tab")
                        }
                        .buttonStyle(.link)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack {
            Toggle(isOn: $manualParams) {
                Text("Manually choose parameters")
            }
            .toggleStyle(.switch)
            Spacer()
            if let dataset = modelManager.activeDataset {
                Label {
                    Text("Using \(dataset.name)")
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .foregroundColor(.secondary)
            }
        }
    }

    private var filteredModels: [LocalModel] {
        var base = models.filter(\.isDownloaded)
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            base = base.filter {
                $0.name.lowercased().contains(needle)
                || $0.modelID.lowercased().contains(needle)
                || $0.quant.lowercased().contains(needle)
                || $0.architectureFamily.lowercased().contains(needle)
            }
        }
        switch sort {
        case .recent:
            base.sort {
                let lhs = $0.lastUsedDate ?? $0.downloadDate
                let rhs = $1.lastUsedDate ?? $1.downloadDate
                return lhs > rhs
            }
        case .size:
            base.sort { $0.sizeGB > $1.sizeGB }
        case .name:
            base.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return base
    }

    private func presentSettings(for model: LocalModel) {
        isPresented = false
        macModalPresenter.present(
            title: model.name,
            subtitle: String(localized: "Model Settings"),
            showCloseButton: true,
            dimensions: .modelSettings,
            contentInsets: EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24)
        ) {
            ModelSettingsView(model: model) { settings in
                macModalPresenter.dismiss()
                startLoad(for: model, settings: settings)
            }
            .environmentObject(modelManager)
            .environmentObject(chatVM)
            .environmentObject(walkthrough)
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
            defer { loadingModelID = nil }
            let success = await performModelLoad(
                model: model,
                settings: settings,
                chatVM: chatVM,
                modelManager: modelManager,
                tabRouter: tabRouter
            )
            if success {
                isPresented = false
            }
        }
    }
}

private struct MacModelRow: View {
    let model: LocalModel
    let isLoading: Bool
    let activeModelID: LocalModel.ID?
    let manualParams: Bool
    let onSelect: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if model.isFavourite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.yellow)
                        }
                        if model.isMultimodal {
                            Image(systemName: "photo")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        if model.isToolCapable {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        if !model.quant.isEmpty && model.format != .slm {
                            capsuleLabel(model.quant)
                        }
                        capsuleLabel(model.format.rawValue.uppercased())
                        if !model.architectureFamily.isEmpty && model.format != .slm {
                            capsuleLabel(model.architectureFamily.uppercased())
                        }
                    }
                }
                Spacer()
                Text(formattedSize)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                activeModelID == model.id
                    ? Color.accentColor.opacity(0.2)
                    : Color.primary.opacity(0.06)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func capsuleLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }

    private var formattedSize: String {
        let bytes = Int64(model.sizeGB * 1_073_741_824.0)
        return localizedByteCountString(bytes: bytes, locale: locale)
    }
}

@MainActor
private func performModelLoad(
    model: LocalModel,
    settings: ModelSettings,
    chatVM: ChatVM,
    modelManager: AppModelManager,
    tabRouter: TabRouter
) async -> Bool {
    let locale = LocalizationManager.preferredLocale()
    if model.format == .slm {
#if canImport(LeapSDK)
        do {
            LeapBundleDownloader.sanitizeBundleIfNeeded(at: model.url)
            let runner = try await Leap.load(url: model.url)
            chatVM.activate(runner: runner, url: model.url)
            modelManager.updateSettings(ModelSettings.default(for: .slm), for: model)
            modelManager.markModelUsed(model)
            modelManager.loadedModel = model
            modelManager.activeRemoteSession = nil
            tabRouter.selection = .chat
            return true
        } catch {
            chatVM.loadError = error.localizedDescription
            modelManager.loadedModel = nil
            return false
        }
#else
        chatVM.loadError = String(localized: "SLM models are not supported on this platform.")
        modelManager.loadedModel = nil
        return false
#endif
    }

    await chatVM.unload()
    try? await Task.sleep(nanoseconds: 200_000_000)

    let bypass = UserDefaults.standard.bool(forKey: "bypassRAMCheck")
    if !bypass {
        let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
        let context = Int(settings.contextLength)
        let layerHint = model.totalLayers > 0 ? model.totalLayers : nil
        if !ModelRAMAdvisor.fitsInRAM(
            format: model.format,
            sizeBytes: sizeBytes,
            contextLength: context,
            layerCount: layerHint,
            moeInfo: model.moeInfo
        ) {
            chatVM.loadError = String(localized: "Model likely exceeds memory budget. Lower context or choose a smaller quant.")
            return false
        }
    }

    var pendingFlagSet = false
    defer {
        if pendingFlagSet {
            UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
        }
    }

    UserDefaults.standard.set(true, forKey: "bypassRAMLoadPending")
    pendingFlagSet = true

    var loadURL = model.url
    switch model.format {
    case .gguf:
        loadURL = resolveGGUFURL(from: loadURL, model: model)
    case .mlx:
        loadURL = resolveMLXURL(from: loadURL, model: model)
    case .slm:
        break
    case .apple:
        chatVM.loadError = String(localized: "Apple bundle models aren't supported on macOS yet.")
        modelManager.loadedModel = nil
        return false
    }

    guard loadURL != URL(fileURLWithPath: "/dev/null") else {
        return false
    }

    if await chatVM.load(url: loadURL, settings: settings, format: model.format) {
        modelManager.updateSettings(settings, for: model)
        modelManager.markModelUsed(model)
        modelManager.loadedModel = model
        modelManager.activeRemoteSession = nil
        tabRouter.selection = .chat
        return true
    } else {
        modelManager.loadedModel = nil
        return false
    }
}

private func resolveGGUFURL(from url: URL, model: LocalModel) -> URL {
    var resolved = url
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) {
        if isDir.boolValue {
            if let candidate = InstalledModelsStore.firstGGUF(in: resolved) {
                resolved = candidate
            }
        } else if resolved.pathExtension.lowercased() != "gguf" {
            if let candidate = InstalledModelsStore.firstGGUF(in: resolved.deletingLastPathComponent()) {
                resolved = candidate
            }
        }
    } else if let candidate = InstalledModelsStore.firstGGUF(in: InstalledModelsStore.baseDir(for: .gguf, modelID: model.modelID)) {
        resolved = candidate
    } else {
        resolved = URL(fileURLWithPath: "/dev/null")
    }
    return resolved
}

private func resolveMLXURL(from url: URL, model: LocalModel) -> URL {
    var resolved = url
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) {
        resolved = isDir.boolValue ? resolved : resolved.deletingLastPathComponent()
    } else {
        let base = InstalledModelsStore.baseDir(for: .mlx, modelID: model.modelID)
        if FileManager.default.fileExists(atPath: base.path, isDirectory: &isDir), isDir.boolValue {
            resolved = base
        } else {
            resolved = URL(fileURLWithPath: "/dev/null")
        }
    }
    return resolved
}
#endif
