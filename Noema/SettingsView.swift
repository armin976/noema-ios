// SettingsView.swift
import SwiftUI
#if canImport(UIKit) && !os(visionOS)
import UIKit
#endif

final class SettingsModel: ObservableObject {
    @AppStorage("isAdvancedMode") var isAdvancedMode = false {
        didSet { objectWillChange.send() }
    }
    @AppStorage("offGrid") var offGrid = false
    @AppStorage("appearance") var appearance = "system" // light, dark, system
    @AppStorage("defaultModelPath") var defaultModelPath = ""
    @AppStorage("verboseLogging") var verboseLogging = false
    @AppStorage("huggingFaceToken") var huggingFaceToken = ""
    @AppStorage("bypassRAMCheck") var bypassRAMCheck = false
#if os(visionOS)
    @AppStorage("visionVerticalPanelLayout") var visionVerticalPanelLayout = true
#endif
    // System preset removed; default system behavior is always used
    @AppStorage("ragMaxChunks") var ragMaxChunks = 5
    @AppStorage("ragMinScore") var ragMinScore: Double = 0.5

    // MCPs removed

    /// Clears all chat sessions. This mutates `ChatVM.sessions` which lives on
    /// the `MainActor`, so ensure we're also on the main actor when calling it.
    @MainActor
    func clearChatHistory(_ vm: ChatVM) {
        vm.sessions.removeAll()
        vm.startNewSession()
    }

    @MainActor
    func resetAppData() {
        objectWillChange.send()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        ModelSettingsStore.clear()
        // Restore default values so UI reflects the reset immediately.
        isAdvancedMode = false
        offGrid = false
        appearance = "system"
        defaultModelPath = ""
        verboseLogging = false
        huggingFaceToken = ""
        bypassRAMCheck = false
        ragMaxChunks = 5
        ragMinScore = 0.5
    }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsModel()
    @EnvironmentObject var chatVM: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var walkthrough: GuidedWalkthroughManager
    @Environment(\.dismiss) private var dismiss
    @State private var showOnboarding = false
    @State private var showLogs = false
    @State private var shareLogs = false
    @State private var showChatsCleared = false
    @State private var confirmClearChats = false
    @State private var confirmResetAppData = false
    @State private var showResetComplete = false
    @State private var isResettingAppData = false
    @State private var showRAMInfo = false
    @State private var showChunksInfo = false
    @State private var showSimilarityInfo = false
    @State private var estimateModelPath: String = ""
    @State private var embedAvailable = FileManager.default.fileExists(atPath: EmbeddingModel.modelURL.path)
    @State private var showEmbedDeleteError = false
    @State private var embedDeleteErrorMessage = ""
    private let llamaCppBuild = "b6653"
    private enum ScrollTarget: Hashable {
        case offGrid
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    if !DeviceGPUInfo.supportsGPUOffload {
                        Section {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("This device doesn't support GPU offload; GGUF models will run on the CPU and generation speed will be significantly slower.")
                                        .font(.caption)
                                    Text("Fastest option on this device: SLM (Leap) models.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .listRowBackground(Color.yellow.opacity(0.1))
                    }
                    modeSection
                    ramSection
                    Section {
                        Toggle("Bypass RAM safety check (may cause crashes)", isOn: $settings.bypassRAMCheck)
                        Text("If enabled, the app will attempt to load models even when they likely exceed your device's memory budget. This can cause the app to terminate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SettingsWebSearchSection()
                    Section {
                        Toggle("Off-grid Mode", isOn: $settings.offGrid)
                            .id(ScrollTarget.offGrid)
                            .guideHighlight(.settingsOffGrid)
                            .onChange(of: settings.offGrid) { on in
                                NetworkKillSwitch.setEnabled(on)
                            }
                        Text("Blocks all network traffic, model downloads, and cloud connections so everything stays on‑device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                    }
                    generalSection
                    Section("Embedding Model") {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nomic Embed Text v1.5 (Q4_K_M)")
                                Text("High-quality embedding model for local RAG")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: embedAvailable ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(embedAvailable ? .green : .secondary)
                                .imageScale(.large)
                                .accessibilityLabel(embedAvailable ? "Embedding model downloaded" : "Embedding model missing")
                        }
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if embedAvailable {
                                Button(role: .destructive) {
                                    deleteEmbeddingModel()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }

                        Text(embedAvailable ? "Swipe left to remove the embedding model from this device." : "Not downloaded. Open onboarding to install the embedding model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    // System prompt selection removed; always use default system behavior
                    if settings.isAdvancedMode {
                        advancedSection
                    }
                    privacySection
                    aboutSection
                    llamaCppSection
                }
                .guideHighlight(.settingsForm)
                .onChange(of: walkthrough.step) { step in
                    guard step == .settingsHighlights else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut) {
                            proxy.scrollTo(ScrollTarget.offGrid, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    if walkthrough.step == .settingsHighlights {
                        DispatchQueue.main.async {
                            proxy.scrollTo(ScrollTarget.offGrid, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                if !modelManager.downloadedModels.contains(where: { $0.url.path == settings.defaultModelPath }) {
                    settings.defaultModelPath = ""
                }
                refreshEmbeddingAvailability()
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(showOnboarding: $showOnboarding)
            }
            .onReceive(modelManager.$downloadedModels) { models in
                if !models.contains(where: { $0.url.path == settings.defaultModelPath }) {
                    settings.defaultModelPath = ""
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .embeddingModelAvailabilityChanged)) { notification in
                if let available = notification.userInfo?["available"] as? Bool {
                    embedAvailable = available
                } else {
                    refreshEmbeddingAvailability()
                }
            }
            .navigationDestination(isPresented: $showLogs) {
                LogViewerView(url: Logger.shared.logFileURL)
            }
            .sheet(isPresented: $shareLogs) {
                ShareLink(item: Logger.shared.logFileURL) {
                    Text("Share Logs")
                }
            }
            .alert("Chat History Deleted", isPresented: $showChatsCleared) {
                Button("OK", role: .cancel) {}
            }
            .alert("App Data Reset", isPresented: $showResetComplete) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Noema has been reset. The embedding model remains installed.")
            }
            .confirmationDialog("Delete All Chats", isPresented: $confirmClearChats, titleVisibility: .visible) {
                Button("Delete All Chats", role: .destructive) {
                    settings.clearChatHistory(chatVM)
                    showChatsCleared = true
                    confirmClearChats = false
                }
                Button("Cancel", role: .cancel) { confirmClearChats = false }
            } message: {
                Text("This permanently removes every chat conversation. This action cannot be undone.")
            }
            .confirmationDialog("Reset App Data", isPresented: $confirmResetAppData, titleVisibility: .visible) {
                Button("Reset App Data", role: .destructive) {
                    Task { await performResetAppData() }
                }
                Button("Cancel", role: .cancel) { confirmResetAppData = false }
            } message: {
                Text("Deletes all chats, downloaded models, and datasets, and restores settings to defaults. The embedding model stays installed.")
            }
            .alert("About RAM Usage", isPresented: $showRAMInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The app memory usage budget is an estimate based on your device's total RAM and typical iOS memory management. The actual available memory may vary depending on system load, other running apps, and iOS memory pressure. Models that exceed this budget may cause the app to be terminated by iOS.")
            }
            .alert("Max Chunks", isPresented: $showChunksInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Controls how many high‑scoring passages (chunks) can be injected into the prompt. Higher values increase recall but consume more context window and can slow responses. Typical range 3–6.")
            }
            .alert("Similarity Threshold", isPresented: $showSimilarityInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Minimum cosine similarity a passage must have to be considered relevant. Lower = more passages (higher recall, more noise). Higher = fewer, more precise passages. Try 0.2–0.4 for broad questions; 0.5–0.7 for precise lookups.")
            }
            .alert("Failed to Delete Embedding Model", isPresented: $showEmbedDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(embedDeleteErrorMessage)
            }
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $settings.isAdvancedMode) {
                Text("Simple").tag(false)
                Text("Advanced").tag(true)
            }
            .pickerStyle(.segmented)
            Text(modeExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var ramSection: some View {
        let info = DeviceRAMInfo.current()
        let budgetText: String = {
            if let b = info.conservativeLimitBytes() {
                return ByteCountFormatter.string(fromByteCount: b, countStyle: .memory)
            }
            let limitClean = info.limit.replacingOccurrences(of: "~", with: "").trimmingCharacters(in: .whitespaces)
            return limitClean
        }()
        // Choose model for estimate: explicit picker selection if set; else loaded; else default; else first
        let selectedPath = !estimateModelPath.isEmpty ? estimateModelPath : (modelManager.loadedModel?.url.path ?? settings.defaultModelPath)
        let modelForEstimate: LocalModel? = modelManager.downloadedModels.first(where: { $0.url.path == selectedPath }) ?? modelManager.loadedModel ?? modelManager.downloadedModels.first
        let estimateText: String? = {
            guard let m = modelForEstimate else { return nil }
            // Use saved settings for this model to pick context length
            let settings = modelManager.settings(for: m)
            let sizeBytes = Int64(m.sizeGB * 1_073_741_824.0)
            let ctx = Int(settings.contextLength)
            let layerHint: Int? = m.totalLayers > 0 ? m.totalLayers : nil
            let (estimate, _) = ModelRAMAdvisor.estimateAndBudget(format: m.format, sizeBytes: sizeBytes, contextLength: ctx, layerCount: layerHint)
            return ByteCountFormatter.string(fromByteCount: estimate, countStyle: .memory)
        }()
        return Section {
            GroupBox {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(info.ram) – \(info.modelName)")
                            .fontWeight(.medium)
                        Text("App memory usage budget: \(budgetText) (conservative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let m = modelForEstimate, let est = estimateText {
                            // Clarify which model and context length the estimate refers to
                            Text("Working set estimate (\(m.name)): \(est) @ \(Int(modelManager.settings(for: m).contextLength)) tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if info.limit == "--" {
                            Text("RAM information for this device will be added in a future update.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: { showRAMInfo = true }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.system(size: 20))
                    }
                }
                .padding(4)
            }
            if settings.isAdvancedMode {
                // Quick estimator: choose a model to preview its working set without changing defaults
                if !modelManager.downloadedModels.isEmpty {
                    Picker("Estimate for", selection: $estimateModelPath) {
                        ForEach(modelManager.downloadedModels, id: \.url) { m in
                            Text(m.name).tag(m.url.path)
                        }
                    }
                    .onAppear {
                        if estimateModelPath.isEmpty {
                            estimateModelPath = modelForEstimate?.url.path ?? ""
                        }
                    }
                }
                LiveRAMUsageView(info: info)
            }
        }
    }

    private var generalSection: some View {
        Section("General") {
#if os(visionOS)
            Toggle("Show vertical workspace", isOn: $settings.visionVerticalPanelLayout)
            Text("Swap between the new stacked chat panel and the classic tab bar layout.")
                .font(.caption)
                .foregroundStyle(.secondary)
#endif

            Picker("Appearance", selection: $settings.appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }

            Picker("Default Model", selection: $settings.defaultModelPath) {
                Text("None").tag("")
                ForEach(modelManager.downloadedModels, id: \.url) { model in
                    Text(model.name).tag(model.url.path)
                }
            }
            .onChange(of: settings.defaultModelPath) { _, newValue in
                // Ensure the selected default exists, otherwise clear.
                if !newValue.isEmpty && !modelManager.downloadedModels.contains(where: { $0.url.path == newValue }) {
                    settings.defaultModelPath = ""
                }
            }

            Button("Reopen Onboarding") {
                triggerImpact(.medium)
                showOnboarding = true
            }

        }
    }

    // System prompt section fully removed


    // Title section removed

    private var privacySection: some View {
        Section("Privacy") {
            Button("Delete All Chats") {
                triggerImpact(.medium)
                confirmClearChats = true
            }
            .tint(.red)
            Button("Reset App Data") {
                triggerImpact(.medium)
                confirmResetAppData = true
            }
            .tint(.red)
            .disabled(isResettingAppData)
        }
    }

    private var aboutSection: some View {
        Section("About & Support") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            Link("Terms of Use", destination: URL(string: "https://noemaai.com/terms")!)
            Link("Privacy Policy", destination: URL(string: "https://noemaai.com/privacy")!)
            Link("Contact Support", destination: URL(string: "mailto:noema.clientcare@gmail.com")!)
            NavigationLink("Notes & Issues") {
                DisclaimerView()
            }
        }
    }

    private var llamaCppSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Llama.cpp")
                    .fontWeight(.medium)
                Text("Latest integrated release: \(llamaCppBuild)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Image("Noema")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Noema")
                        .fontWeight(.medium)
                    Text("Version 1.4")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } footer: {
            Text("This app bundles llama.cpp; we keep this in sync with upstream b‑releases.")
        }
    }

    private var advancedSection: some View {
        Group {
            Section("Retrieval") {
                Stepper(value: $settings.ragMaxChunks, in: 1...8) {
                    HStack(spacing: 8) {
                        Text("Max Chunks: \(settings.ragMaxChunks)")
                        Spacer()
                        Button { showChunksInfo = true } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("What is Max Chunks?")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Similarity Threshold")
                        Button { showSimilarityInfo = true } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("What is Similarity Threshold?")
                        Spacer()
                        Text(String(format: "%.2f", settings.ragMinScore))
                            .frame(width: 44, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.ragMinScore, in: 0...1)
                    Text("Lower = more results (more noise). Higher = stricter matches.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            // MCPs section removed
        }
    }


    // Auto-title explanation removed

    private var modeExplanation: String {
        settings.isAdvancedMode
            ? "Advanced mode shows developer options and diagnostics."
            : "Simple mode hides advanced settings for a cleaner interface."
    }
}

private extension SettingsView {
    @MainActor
    func performResetAppData() async {
        guard !isResettingAppData else { return }
        isResettingAppData = true
        defer { isResettingAppData = false }

        confirmResetAppData = false
        showChatsCleared = false

        triggerImpact(.heavy)

        await chatVM.unload()
        modelManager.loadedModel = nil
        modelManager.lastUsedModel = nil
        modelManager.activeDataset = nil
        modelManager.modelSettings.removeAll()

        let models = modelManager.downloadedModels
        for model in models {
            modelManager.delete(model)
        }

        let datasets = datasetManager.datasets
        for dataset in datasets {
            try? datasetManager.delete(dataset)
        }
        datasetManager.select(nil)
        modelManager.setActiveDataset(nil)

        settings.clearChatHistory(chatVM)
        estimateModelPath = ""

        await settings.resetAppData()
        NetworkKillSwitch.setEnabled(false)

        modelManager.refresh()
        datasetManager.reloadFromDisk()

        showResetComplete = true
    }

    func refreshEmbeddingAvailability() {
        embedAvailable = FileManager.default.fileExists(atPath: EmbeddingModel.modelURL.path)
    }

    func deleteEmbeddingModel() {
        Task {
            await logger.log("[Settings] User requested embedding model deletion")
            await EmbeddingModel.shared.unload()
            let url = EmbeddingModel.modelURL
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                UserDefaults.standard.removeObject(forKey: "hasInstalledEmbedModel:\(url.path)")
                await MainActor.run {
                    refreshEmbeddingAvailability()
                    NotificationCenter.default.post(name: .embeddingModelAvailabilityChanged, object: nil, userInfo: ["available": false])
                }
                await logger.log("[Settings] ✅ Embedding model deleted")
            } catch {
                await logger.log("[Settings] ❌ Failed to delete embedding model: \(error.localizedDescription)")
                let message = error.localizedDescription
                await MainActor.run {
                    embedDeleteErrorMessage = message
                    showEmbedDeleteError = true
                    refreshEmbeddingAvailability()
                }
            }
        }
    }
}

private enum ImpactStyle {
    case medium
    case heavy
}

private func triggerImpact(_ style: ImpactStyle) {
#if canImport(UIKit) && !os(visionOS)
    let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
    switch style {
    case .medium:
        feedbackStyle = .medium
    case .heavy:
        feedbackStyle = .heavy
    }
    UIImpactFeedbackGenerator(style: feedbackStyle).impactOccurred()
#endif
}

@_silgen_name("app_memory_footprint")
fileprivate func c_app_memory_footprint() -> UInt

private struct LiveRAMUsageView: View {
    let info: DeviceRAMInfo
    @State private var usageBytes: Int64 = 0
    @State private var timer: Timer?

    private var budgetBytes: Int64? {
        // Use the conservative budget the app uses for gating estimates
        return info.conservativeLimitBytes()
    }

    private var progress: Double {
        guard let cap = budgetBytes, cap > 0 else { return 0 }
        return min(1.0, Double(usageBytes) / Double(cap))
    }

    private var color: Color {
        switch progress {
        case 0..<0.7: return .green
        case 0.7..<0.9: return .orange
        default: return .red
        }
    }

    private var usageText: String {
        ByteCountFormatter.string(fromByteCount: usageBytes, countStyle: .memory)
    }

    private var capText: String {
        if let cap = budgetBytes { return ByteCountFormatter.string(fromByteCount: cap, countStyle: .memory) }
        return "--"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 64, height: 64)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Memory Usage (estimated)")
                    Text("\(usageText) of \(capText) budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onAppear { start() }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { @MainActor in refresh() }
        }
        .accessibilityElement(children: .contain)
    }

    private func start() {
        Task { @MainActor in refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in refresh() }
        }
    }

    private func stop() { timer?.invalidate(); timer = nil }

    private func refresh() {
        let bytes = Int64(c_app_memory_footprint())
        withAnimation(.easeInOut(duration: 0.2)) { usageBytes = max(0, bytes) }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ChatVM())
        .environmentObject(AppModelManager())
        .environmentObject(DatasetManager())
}
