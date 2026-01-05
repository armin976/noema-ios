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
        verboseLogging = false
        huggingFaceToken = ""
        bypassRAMCheck = false
        ragMaxChunks = 5
        ragMinScore = 0.5
        StartupPreferencesStore.save(StartupPreferences())
    }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsModel()
    @ObservedObject private var webSettings = SettingsStore.shared
    @EnvironmentObject var chatVM: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var walkthrough: GuidedWalkthroughManager
    @EnvironmentObject var localizationManager: LocalizationManager
    // Installer used to mirror onboarding's embedding model download flow
    @StateObject private var embedInstaller = EmbedModelInstaller()
#if canImport(UIKit)
    @State private var showOnboarding = false
#endif
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
    @State private var startupPreferences = StartupPreferencesStore.load()
    @State private var showWebSearchInfo = false
    @State private var selectedLanguageCode: String = UserDefaults.standard.string(forKey: "appLanguageCode") ?? LocalizationManager.detectSystemLanguage()
    private let llamaCppBuild = "b7313"
    private let appVersion = "2.0"
    private enum ScrollTarget: Hashable {
        case offGrid
    }

    var body: some View {
        NavigationStack {
            settingsContent
                .navigationTitle(LocalizedStringKey("Settings"))
                .onAppear {
                    refreshEmbeddingAvailability()
                    refreshStartupPreferences()
                }
#if canImport(UIKit)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(showOnboarding: $showOnboarding)
                }
#endif
                .onReceive(modelManager.$downloadedModels) { _ in
                    refreshStartupPreferences()
                }
                .onReceive(modelManager.$remoteBackends) { _ in
                    refreshStartupPreferences()
                }
                .onReceive(NotificationCenter.default.publisher(for: .embeddingModelAvailabilityChanged)) { notification in
                    if let available = notification.userInfo?["available"] as? Bool {
                        embedAvailable = available
                    } else {
                        refreshEmbeddingAvailability()
                    }
                }
                .onChange(of: embedInstaller.state) { newValue in
                    // When installation completes, warm up the backend for snappier first use
                    if newValue == .ready {
                        Task { await EmbeddingModel.shared.warmUp() }
                    }
                }
                .onChange(of: localizationManager.locale) { _ in
                    selectedLanguageCode = currentLanguageCode
                }
                .navigationDestination(isPresented: $showLogs) {
                    LogViewerView(url: Logger.shared.logFileURL)
                }
                .sheet(isPresented: $shareLogs) {
                    ShareLink(item: Logger.shared.logFileURL) {
                        Text(LocalizedStringKey("Share Logs"))
                    }
                }
                .alert(LocalizedStringKey("Chat History Deleted"), isPresented: $showChatsCleared) {
                    Button(LocalizedStringKey("OK"), role: .cancel) {}
                }
                .alert(LocalizedStringKey("App Data Reset"), isPresented: $showResetComplete) {
                    Button(LocalizedStringKey("OK"), role: .cancel) {}
                } message: {
                    Text(LocalizedStringKey("Noema has been reset. The embedding model remains installed."))
                }
                .confirmationDialog(LocalizedStringKey("Delete All Chats"), isPresented: $confirmClearChats, titleVisibility: .visible) {
                    Button(LocalizedStringKey("Delete All Chats"), role: .destructive) {
                        settings.clearChatHistory(chatVM)
                        showChatsCleared = true
                        confirmClearChats = false
                    }
                    Button(LocalizedStringKey("Cancel"), role: .cancel) { confirmClearChats = false }
                } message: {
                    Text(LocalizedStringKey("This permanently removes every chat conversation. This action cannot be undone."))
                }
                .confirmationDialog(LocalizedStringKey("Reset App Data"), isPresented: $confirmResetAppData, titleVisibility: .visible) {
                    Button(LocalizedStringKey("Reset App Data"), role: .destructive) {
                        Task { await performResetAppData() }
                    }
                    Button(LocalizedStringKey("Cancel"), role: .cancel) { confirmResetAppData = false }
                } message: {
                    Text(LocalizedStringKey("Deletes all chats, downloaded models, and datasets, and restores settings to defaults. The embedding model stays installed."))
                }
                .alert(LocalizedStringKey("About RAM Usage"), isPresented: $showRAMInfo) {
                    Button(LocalizedStringKey("OK"), role: .cancel) { }
                } message: {
                    Text(LocalizedStringKey("The app memory usage budget is an estimate based on your device's total RAM and typical iOS memory management. The actual available memory may vary depending on system load, other running apps, and iOS memory pressure. Models that exceed this budget may cause the app to be terminated by iOS."))
                }
                .alert(LocalizedStringKey("Max Chunks"), isPresented: $showChunksInfo) {
                    Button(LocalizedStringKey("OK"), role: .cancel) {}
                } message: {
                    Text(LocalizedStringKey("Controls how many high‑scoring passages (chunks) can be injected into the prompt. Higher values increase recall but consume more context window and can slow responses. Typical range 3–6."))
                }
                .alert(LocalizedStringKey("Similarity Threshold"), isPresented: $showSimilarityInfo) {
                    Button(LocalizedStringKey("OK"), role: .cancel) {}
                } message: {
                    Text(LocalizedStringKey("Minimum cosine similarity a passage must have to be considered relevant. Lower = more passages (higher recall, more noise). Higher = fewer, more precise passages. Try 0.2–0.4 for broad questions; 0.5–0.7 for precise lookups."))
                }
                .alert(LocalizedStringKey("Failed to Delete Embedding Model"), isPresented: $showEmbedDeleteError) {
                    Button(LocalizedStringKey("OK"), role: .cancel) {}
                } message: {
                    Text(embedDeleteErrorMessage)
                }
#if os(macOS)
                .frame(minWidth: 640, minHeight: 560)
#endif
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
#if os(macOS)
        macSettingsView
#else
        settingsFormView
#endif
    }

    @ViewBuilder
    private var settingsFormView: some View {
        ScrollViewReader { proxy in
            Form {
                if !DeviceGPUInfo.supportsGPUOffload {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey("This device doesn't support GPU offload; GGUF models will run on the CPU and generation speed will be significantly slower."))
                                    .font(.caption)
                                Text(LocalizedStringKey("Fastest option on this device: SLM (Leap) models."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.yellow.opacity(0.1))
                }
                modeSection
                ramSection
                startupSection
                ramBypassSection
                SettingsWebSearchSection()
                offGridSection
                generalSection
                earlyTestersSection
                embeddingSection
                if settings.isAdvancedMode {
                    advancedSection
                }
                privacySection
                aboutSection
                llamaCppSection
            }
#if os(macOS)
            .formStyle(.grouped)
#endif
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
                    selectedLanguageCode = currentLanguageCode
                }
            }
    }


    private var modeCard: some View {
        SettingsCard(title: LocalizedStringKey("Mode"), icon: "slider.horizontal.3", minHeight: 220) {
            modeSettingsContent
        }
    }

    private enum SettingsPage: String, CaseIterable, Identifiable {
        case general = "General"
        case models = "Models"
        case search = "Search"
        case privacy = "Privacy"
        case advanced = "Advanced"
        case about = "About"
        
        var id: String { rawValue }
        var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
        
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .models: return "cpu"
            case .search: return "magnifyingglass"
            case .privacy: return "hand.raised"
            case .advanced: return "slider.horizontal.3"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedPage: SettingsPage = .general

#if os(macOS)
    @ViewBuilder
    private var macSettingsView: some View {
        HSplitView {
            // Sidebar
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(SettingsPage.allCases) { page in
                            if page == .advanced && !settings.isAdvancedMode {
                                EmptyView()
                            } else {
                                Button(action: { selectedPage = page }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: page.icon)
                                            .font(.system(size: 14))
                                            .frame(width: 20)
                                        Text(page.titleKey)
                                            .font(FontTheme.body)
                                            .fontWeight(.medium)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selectedPage == page ? Color.accentColor.opacity(0.15) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.accentColor.opacity(selectedPage == page ? 0.2 : 0), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(selectedPage == page ? AppTheme.text : AppTheme.secondaryText)
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .frame(minWidth: 200, maxWidth: 240)
            .background(AppTheme.sidebarBackground.ignoresSafeArea())
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text(selectedPage.titleKey)
                        .font(FontTheme.largeTitle)
                        .foregroundStyle(AppTheme.text)
                        .padding(.bottom, 8)
                    
                    settingsContent(for: selectedPage)
                }
                .padding(32)
                .frame(maxWidth: 800, alignment: .leading)
            }
            .frame(minWidth: 400, maxWidth: .infinity)
            .background(AppTheme.windowBackground.ignoresSafeArea())
        }
    }
    
    @ViewBuilder
    private func settingsContent(for page: SettingsPage) -> some View {
        switch page {
        case .general:
            VStack(spacing: 24) {
                if !DeviceGPUInfo.supportsGPUOffload {
                    SettingsNoticeCard(
                        title: String(localized: "CPU Rendering Only"),
                        message: String(localized: "This Mac cannot offload GGUF models to the GPU. Expect slower generation speeds. Leap SLM models remain the fastest option here.")
                    )
                }
                modeCard
                startupCard
                generalCard
            }
        case .models:
            VStack(spacing: 24) {
                ramCard
                ramBypassCard
                embeddingCard
            }
        case .search:
            VStack(spacing: 24) {
                webSearchCard
                offGridCard
            }
        case .privacy:
            privacyCard
        case .advanced:
            advancedCard
        case .about:
            VStack(spacing: 24) {
                aboutCard
                earlyTestersCard
                buildInfoCard
            }
        }
    }
#endif

    private var ramCard: some View {
        let metrics = ramMetrics()
        return SettingsCard(title: LocalizedStringKey("Memory Budget"), icon: "memorychip", minHeight: 220) {
            ramSettingsContent(info: metrics.info,
                               budgetText: metrics.budgetText,
                               modelForEstimate: metrics.model,
                               estimateText: metrics.estimateText)
        }
    }

    private var startupCard: some View {
        SettingsCard(title: LocalizedStringKey("Startup Defaults"), icon: "play.circle", minHeight: 220) {
            startupSettingsContent
        }
    }

    private var ramBypassCard: some View {
        SettingsCard(title: LocalizedStringKey("Runtime Safety"), icon: "shield.lefthalf.filled", minHeight: 220) {
            ramBypassContent
        }
    }

    private var webSearchCard: some View {
        SettingsCard(title: LocalizedStringKey("Search"), icon: "magnifyingglass.circle", minHeight: 220) {
            Toggle(isOn: $webSettings.webSearchEnabled) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey("Web Search button"))
                        .font(FontTheme.body)
                        .foregroundStyle(AppTheme.text)
                    Button { showWebSearchInfo = true } label: {
                        Image(systemName: "questionmark.circle").foregroundStyle(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizedStringKey("What is Web Search button?"))
                }
            }
            .toggleStyle(ModernToggleStyle())
            .tint(.blue)
            .onChangeCompat(of: webSettings.webSearchEnabled) { _, on in
                if !on { webSettings.webSearchArmed = false }
            }

            if webSettings.webSearchEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("SearXNG web search is enabled for this device."))
                        .font(FontTheme.subheadline)
                        .foregroundStyle(AppTheme.text)
                    Text(LocalizedStringKey("Search requests are proxied through https://search.noemaai.com and are available without quotas."))
                        .font(FontTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.top, 4)
            }
        }
        .alert(LocalizedStringKey("Web Search button"), isPresented: $showWebSearchInfo) {
            Button(LocalizedStringKey("OK"), role: .cancel) { }
        } message: {
            Text(LocalizedStringKey("Allows models to use a privacy-preserving web search API when you tap the globe in chat. Default is ON. In Offline Only mode, the button is disabled."))
        }
    }

    private var offGridCard: some View {
        SettingsCard(title: LocalizedStringKey("Network"), icon: "antenna.radiowaves.left.and.right") {
            offGridContent
        }
    }

    private var generalCard: some View {
        SettingsCard(title: LocalizedStringKey("General"), icon: "gearshape", minHeight: 220) {
            generalContent
        }
    }

    private var embeddingCard: some View {
        SettingsCard(title: LocalizedStringKey("Embedding Model"), icon: "square.stack.3d.up", minHeight: 220) {
            embeddingContent
        }
    }

    private var advancedCard: some View {
        SettingsCard(title: LocalizedStringKey("Retrieval"), icon: "doc.text.magnifyingglass", minHeight: 220) {
            advancedRetrievalContent
        }
    }

    private var privacyCard: some View {
        SettingsCard(title: LocalizedStringKey("Privacy"), icon: "hand.raised", minHeight: 220) {
            privacyContent
        }
    }

    private var aboutCard: some View {
        SettingsCard(title: LocalizedStringKey("About & Support"), icon: "info.circle", minHeight: 220) {
            aboutContent
        }
    }

    private var earlyTestersCard: some View {
        SettingsCard(title: LocalizedStringKey("Early Testers"), icon: "sparkles") {
            earlyTestersContent
        }
    }

    private var buildInfoCard: some View {
        SettingsCard(title: LocalizedStringKey("Build Info"), icon: "hare", minHeight: 220) {
            llamaContent
        }
    }

    private struct SettingsCard<Content: View>: View {
        let title: LocalizedStringKey
        let icon: String?
        let content: Content
        let minHeight: CGFloat?

        init(title: LocalizedStringKey, icon: String? = nil, minHeight: CGFloat? = nil, @ViewBuilder content: () -> Content) {
            self.title = title
            self.icon = icon
            self.content = content()
            self.minHeight = minHeight
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Text(title)
                        .font(FontTheme.heading)
                        .foregroundStyle(AppTheme.text)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: minHeight)
            .glassifyIfAvailable(in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .background(AppTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
        }
    }

    private struct SettingsNoticeCard: View {
        let title: String
        let message: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(title)
                        .font(FontTheme.body)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.text)
                }
                Text(message)
                    .font(FontTheme.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private struct AdaptiveColumnsLayout: Layout {
        var minColumnWidth: CGFloat = 360
        var spacing: CGFloat = 24

        private func columnCount(for width: CGFloat) -> Int {
            guard width.isFinite, width > 0 else { return 1 }
            let maxColumns = Int((width + spacing) / (minColumnWidth + spacing))
            return max(1, maxColumns)
        }

        private func measure(width: CGFloat, subviews: Subviews) -> (columns: Int, columnWidth: CGFloat, rowHeights: [CGFloat]) {
            let columns = columnCount(for: width)
            let totalSpacing = spacing * CGFloat(max(0, columns - 1))
            let columnWidth = max(0, (width - totalSpacing) / CGFloat(columns))

            var heights: [CGFloat] = []
            var currentMax: CGFloat = 0
            var col = 0
            for subview in subviews {
                let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                currentMax = max(currentMax, size.height)
                col += 1
                if col == columns {
                    heights.append(currentMax)
                    currentMax = 0
                    col = 0
                }
            }
            if col != 0 { heights.append(currentMax) }
            return (columns, columnWidth, heights)
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let availableWidth = proposal.width ?? minColumnWidth
            let metrics = measure(width: availableWidth, subviews: subviews)
            let rows = metrics.rowHeights
            let totalHeight = rows.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
            return CGSize(width: availableWidth, height: totalHeight)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let metrics = measure(width: bounds.width, subviews: subviews)
            let columns = metrics.columns
            let columnWidth = metrics.columnWidth
            let rowHeights = metrics.rowHeights

            var x = bounds.minX
            var y = bounds.minY
            var columnIndex = 0
            var rowIndex = 0

            for (idx, subview) in subviews.enumerated() {
                if columnIndex == columns {
                    columnIndex = 0
                    rowIndex += 1
                    x = bounds.minX
                    y += rowHeights[rowIndex - 1] + spacing
                }

                let proposedHeight = rowHeights[rowIndex]
                let proposed = ProposedViewSize(width: columnWidth, height: proposedHeight)
                let size = subview.sizeThatFits(proposed)
                // Place at top-left of the row area
                subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: columnWidth, height: proposedHeight)
                )

                columnIndex += 1
                x += columnWidth + spacing
                _ = size // keep for potential debug
                _ = idx
            }
        }
    }

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
                            .font(FontTheme.caption)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.text)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey("App Memory Usage (estimated)"))
                            .font(FontTheme.body)
                            .foregroundStyle(AppTheme.text)
                        Text(String.localizedStringWithFormat(String(localized: "%@ of %@ budget"), usageText, capText))
                            .font(FontTheme.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                }
            }
            .onAppear { start() }
            .onDisappear { stop() }
#if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                Task { @MainActor in refresh() }
            }
#endif
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

    private var modeSection: some View {
        Section { modeSettingsContent }
    }

    @ViewBuilder
    private var modeSettingsContent: some View {
        Picker(LocalizedStringKey("Mode"), selection: $settings.isAdvancedMode) {
            Text(LocalizedStringKey("Simple")).tag(false)
            Text(LocalizedStringKey("Advanced")).tag(true)
        }
        .pickerStyle(.segmented)
        Text(modeExplanation)
            .font(FontTheme.caption)
            .foregroundStyle(AppTheme.secondaryText)
    }

    private func ramMetrics() -> (info: DeviceRAMInfo, budgetText: String, model: LocalModel?, estimateText: String?) {
        let info = DeviceRAMInfo.current()
        let byteFormatter: ByteCountFormatter = {
            let f = ByteCountFormatter()
            f.allowedUnits = [.useGB, .useMB]
            f.countStyle = .memory
            return f
        }()
        let budgetText: String = {
            if let b = info.conservativeLimitBytes() {
                return byteFormatter.string(fromByteCount: b)
            }
            let limitClean = info.limit.replacingOccurrences(of: "~", with: "").trimmingCharacters(in: .whitespaces)
            return limitClean
        }()
        // Choose model for estimate: explicit picker selection if set; else loaded; else default; else first
        let selectedPath = !estimateModelPath.isEmpty ? estimateModelPath : (modelManager.loadedModel?.url.path ?? (startupPreferences.localModelPath ?? ""))
        let modelForEstimate: LocalModel? = modelManager.downloadedModels.first(where: { $0.url.path == selectedPath }) ?? modelManager.loadedModel ?? modelManager.downloadedModels.first
        let estimateText: String? = {
            guard let m = modelForEstimate else { return nil }
            // Use saved settings for this model to pick context length
            let settings = modelManager.settings(for: m)
            let sizeBytes = Int64(m.sizeGB * 1_073_741_824.0)
            let ctx = Int(settings.contextLength)
            let layerHint: Int? = m.totalLayers > 0 ? m.totalLayers : nil
            let (estimate, _) = ModelRAMAdvisor.estimateAndBudget(
                format: m.format,
                sizeBytes: sizeBytes,
                contextLength: ctx,
                layerCount: layerHint,
                moeInfo: m.moeInfo
            )
            return byteFormatter.string(fromByteCount: estimate)
        }()
        return (info, budgetText, modelForEstimate, estimateText)
    }

    private var ramSection: some View {
        let metrics = ramMetrics()
        return Section { ramSettingsContent(info: metrics.info,
                                            budgetText: metrics.budgetText,
                                            modelForEstimate: metrics.model,
                                            estimateText: metrics.estimateText) }
    }

    @ViewBuilder
    private func ramSettingsContent(info: DeviceRAMInfo,
                                    budgetText: String,
                                    modelForEstimate: LocalModel?,
                                    estimateText: String?) -> some View {
        GroupBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(info.ram) – \(info.modelName)")
                        .font(FontTheme.body)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.text)
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "App memory usage budget: %@ (conservative)", locale: localizationManager.locale),
                            budgetText
                        )
                    )
                        .font(FontTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    if let m = modelForEstimate, let est = estimateText {
                        // Clarify which model and context length the estimate refers to
                        let ctx = Int(modelManager.settings(for: m).contextLength)
                        let ctxFormatter: NumberFormatter = {
                            let nf = NumberFormatter()
                            nf.locale = localizationManager.locale
                            nf.numberStyle = .decimal
                            return nf
                        }()
                        let ctxString = ctxFormatter.string(from: NSNumber(value: ctx)) ?? "\(ctx)"
                            Text(
                                String.localizedStringWithFormat(
                                    String(localized: "Working set estimate (%@): %@ @ %@ tokens", locale: localizationManager.locale),
                                    m.name,
                                    est,
                                    ctxString
                            )
                        )
                        .font(FontTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                    if info.limit == "--" {
                        Text(LocalizedStringKey("RAM information for this device will be added in a future update."))
                            .font(FontTheme.caption)
                            .foregroundStyle(AppTheme.secondaryText)
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
                Picker(LocalizedStringKey("Estimate for"), selection: $estimateModelPath) {
                    ForEach(modelManager.downloadedModels, id: \.url) { m in
                        Text(m.name).tag(m.url.path)
                    }
                }
                .onAppear {
                    if estimateModelPath.isEmpty {
                        estimateModelPath = modelForEstimate?.url.path ?? (startupPreferences.localModelPath ?? "")
                    }
                }
            }
            LiveRAMUsageView(info: info)
        }
    }

    private var startupSection: some View {
        Section(LocalizedStringKey("Startup")) { startupSettingsContent }
    }

    @ViewBuilder
    private var startupSettingsContent: some View {
        localStartupPicker
        remoteStartupConfigurator
        priorityControls
    }

    private var ramBypassSection: some View {
        Section { ramBypassContent }
    }

    @ViewBuilder
    private var ramBypassContent: some View {
        Toggle(LocalizedStringKey("Bypass RAM safety check (may cause crashes)"), isOn: $settings.bypassRAMCheck)
            .toggleStyle(ModernToggleStyle())
        Text(LocalizedStringKey("If enabled, the app will attempt to load models even when they likely exceed your device's memory budget. This can cause the app to terminate."))
            .font(FontTheme.caption)
            .foregroundStyle(AppTheme.secondaryText)
    }

    private var offGridSection: some View {
        Section { offGridContent }
    }

    @ViewBuilder
    private var offGridContent: some View {
        Toggle(LocalizedStringKey("Off-grid Mode"), isOn: $settings.offGrid)
            .toggleStyle(ModernToggleStyle())
            .id(ScrollTarget.offGrid)
            .guideHighlight(.settingsOffGrid)
            .onChange(of: settings.offGrid) { on in
                NetworkKillSwitch.setEnabled(on)
            }
        Text(LocalizedStringKey("Blocks all network traffic, model downloads, and cloud connections so everything stays on‑device."))
            .font(FontTheme.caption)
            .foregroundStyle(AppTheme.secondaryText)
    }

    private var localStartupPicker: some View {
        Group {
            if modelManager.downloadedModels.isEmpty {
                Text(LocalizedStringKey("Install a local model to make it available at launch."))
                    .font(FontTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Picker(LocalizedStringKey("Local default"), selection: Binding(
                    get: { startupPreferences.localModelPath ?? "" },
                    set: { newValue in
                        updateStartupPreferences { prefs in
                            prefs.localModelPath = newValue.isEmpty ? nil : newValue
                        }
                    }
                )) {
                    Text(LocalizedStringKey("None")).tag("")
                    ForEach(modelManager.downloadedModels, id: \.url) { model in
                        Text(model.name).tag(model.url.path)
                    }
                }
            }
        }
    }

    private var remoteStartupConfigurator: some View {
        Group {
            if modelManager.remoteBackends.isEmpty {
                Text(LocalizedStringKey("Add a remote backend to configure remote startup fallbacks."))
                    .font(FontTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(startupPreferences.remoteSelections.enumerated()), id: \.element.id) { index, selection in
                        StartupRemoteRow(
                            selection: Binding(
                                get: { startupPreferences.remoteSelections[index] },
                                set: { updated in
                                    updateStartupPreferences { prefs in
                                        prefs.remoteSelections[index] = updated
                                    }
                                }
                            ),
                            backend: modelManager.remoteBackends.first(where: { $0.id == selection.backendID }),
                            canMoveUp: index > 0,
                            canMoveDown: index < startupPreferences.remoteSelections.count - 1,
                            moveUp: { moveRemoteSelection(from: index, to: index - 1) },
                            moveDown: { moveRemoteSelection(from: index, to: index + 1) },
                            remove: { removeRemoteSelection(at: index) }
                        )
                    }
                    if let available = availableRemoteBackends, !available.isEmpty {
                        Menu {
                            ForEach(available, id: \.id) { backend in
                                Button(backend.name) {
                                    addRemoteSelection(for: backend)
                                }
                            }
                        } label: {
                            Label(LocalizedStringKey("Add remote default"), systemImage: "plus")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var priorityControls: some View {
        // Only render this block when there is at least one
        // remote selection; otherwise an empty container would
        // create a blank row with a divider in the Section.
        if startupPreferences.hasRemoteSelection {
            VStack(alignment: .leading, spacing: 12) {
                if startupPreferences.hasLocalSelection {
                    Picker(LocalizedStringKey("When both are available"), selection: Binding(
                        get: { startupPreferences.priority },
                        set: { newValue in updateStartupPreferences { $0.priority = newValue } }
                    )) {
                        ForEach(StartupPreferences.Priority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Stepper(value: Binding(
                    get: { startupPreferences.remoteTimeout },
                    set: { newValue in updateStartupPreferences { $0.remoteTimeout = newValue } }
                ), in: StartupPreferences.minTimeout...StartupPreferences.maxTimeout, step: 1) {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "Remote timeout: %ds"),
                            Int(startupPreferences.remoteTimeout)
                        )
                    )
                }
                Text(LocalizedStringKey("We'll try remote models in priority order for this long before moving to the next option."))
                    .font(FontTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var availableRemoteBackends: [RemoteBackend]? {
        let used = Set(startupPreferences.remoteSelections.map { $0.backendID })
        let filtered = modelManager.remoteBackends.filter { !used.contains($0.id) }
        return filtered.isEmpty ? nil : filtered
    }

    private func addRemoteSelection(for backend: RemoteBackend) {
        let initialModel = backend.cachedModels.first
        let selection = StartupPreferences.RemoteSelection(
            backendID: backend.id,
            backendName: backend.name,
            modelID: initialModel?.id ?? "",
            modelName: initialModel?.name ?? "",
            relayRecordName: initialModel?.relayRecordName
        )
        updateStartupPreferences { prefs in
            prefs.remoteSelections.append(selection)
        }
    }

    private func moveRemoteSelection(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < startupPreferences.remoteSelections.count,
              destination >= 0, destination < startupPreferences.remoteSelections.count else { return }
        updateStartupPreferences { prefs in
            let item = prefs.remoteSelections.remove(at: source)
            prefs.remoteSelections.insert(item, at: destination)
        }
    }

    private func removeRemoteSelection(at index: Int) {
        guard index >= 0, index < startupPreferences.remoteSelections.count else { return }
        updateStartupPreferences { prefs in
            prefs.remoteSelections.remove(at: index)
        }
    }

    private func updateStartupPreferences(_ mutate: (inout StartupPreferences) -> Void) {
        var updated = startupPreferences
        mutate(&updated)
        updated.normalize()
        startupPreferences = updated
        StartupPreferencesStore.save(updated)
    }

    private func refreshStartupPreferences() {
        let latest = StartupPreferencesStore.load()
        let sanitized = StartupPreferencesStore.sanitize(preferences: latest,
                                                         models: modelManager.downloadedModels,
                                                         backends: modelManager.remoteBackends)
        if sanitized != startupPreferences {
            startupPreferences = sanitized
        } else if latest != startupPreferences {
            startupPreferences = sanitized
        }
    }

    private var embeddingSection: some View {
        Section(LocalizedStringKey("Embedding Model")) { embeddingContent }
    }

    @ViewBuilder
    private var embeddingContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nomic Embed Text v1.5 (Q4_K_M)")
                    .font(FontTheme.body)
                    .foregroundStyle(AppTheme.text)
                Text(LocalizedStringKey("High-quality embedding model for local RAG"))
                    .font(FontTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Image(systemName: embedAvailable ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(embedAvailable ? .green : AppTheme.secondaryText)
                .imageScale(.large)
                .accessibilityLabel(embedAvailable ? "Embedding model downloaded" : "Embedding model missing")
        }
        .contentShape(Rectangle())
        // Keep swipe-to-delete on iOS, but provide explicit button on macOS where swiping is awkward
        .modifier(EmbeddingSwipeModifier(embedAvailable: embedAvailable, onDelete: deleteEmbeddingModel))

        // Action controls
        Group {
            if embedAvailable {
#if os(macOS)
                // macOS: explicit destructive button instead of swipe
                Button(role: .destructive) {
                    deleteEmbeddingModel()
                } label: {
                    Label(LocalizedStringKey("Delete Embedding Model"), systemImage: "trash")
                }
                .padding(.top, 6)
                Text(LocalizedStringKey("The embedding model is installed. Delete it to free ~320 MB."))
                    .font(FontTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.top, 2)
#else
                Text(LocalizedStringKey("Swipe left to remove the embedding model from this device."))
                    .font(FontTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.top, 4)
#endif
            } else {
                // Not installed: mirror onboarding's installer flow
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        startEmbeddingDownloadFromSettings()
                    } label: {
                        if case .downloading = embedInstaller.state {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(LocalizedStringKey("Downloading…"))
                            }
                        } else if case .verifying = embedInstaller.state {
                            Label(LocalizedStringKey("Verifying…"), systemImage: "checkmark.shield")
                        } else if case .installing = embedInstaller.state {
                            Label(LocalizedStringKey("Installing…"), systemImage: "square.and.arrow.down.on.square")
                        } else {
                            Label(LocalizedStringKey("Download Embedding Model"), systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(embedInstaller.state == .downloading || embedInstaller.state == .verifying || embedInstaller.state == .installing)

                    if embedInstaller.progress > 0 && embedInstaller.progress < 1 {
                        ProgressView(value: embedInstaller.progress)
                            .tint(.blue)
                            .frame(maxWidth: 280)
                    }
                    Text(LocalizedStringKey("320 MB • One‑time download used for local dataset search"))
                        .font(FontTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.top, 6)
            }
        }
    }

    private var generalSection: some View {
        Section(LocalizedStringKey("General")) { generalContent }
    }

    @ViewBuilder
    private var generalContent: some View {
#if os(visionOS)
        Toggle(LocalizedStringKey("Show vertical workspace"), isOn: $settings.visionVerticalPanelLayout)
            .toggleStyle(ModernToggleStyle())
        Text(LocalizedStringKey("Swap between the new stacked chat panel and the classic tab bar layout."))
            .font(FontTheme.caption)
            .foregroundStyle(AppTheme.secondaryText)
#endif

        Picker(LocalizedStringKey("Appearance"), selection: $settings.appearance) {
            Text(LocalizedStringKey("System")).tag("system")
            Text(LocalizedStringKey("Light")).tag("light")
            Text(LocalizedStringKey("Dark")).tag("dark")
        }

        Picker(LocalizedStringKey("Language"), selection: $selectedLanguageCode) {
            ForEach(languageOptions, id: \.code) { option in
                Text(option.name).tag(option.code)
            }
        }
        .onChange(of: selectedLanguageCode) { newValue in
            localizationManager.updateLanguage(code: newValue)
        }
        Text(LocalizedStringKey("Override the app language. Defaults to the device language on first launch."))
            .font(FontTheme.caption)
            .foregroundStyle(AppTheme.secondaryText)

#if canImport(UIKit)
        Button(LocalizedStringKey("Reopen Onboarding")) {
            triggerImpact(.medium)
            showOnboarding = true
        }
#endif
    }

    private var earlyTestersSection: some View {
        Section(LocalizedStringKey("Early Testers")) { earlyTestersContent }
    }

    @ViewBuilder
    private var earlyTestersContent: some View {
        Link(LocalizedStringKey("Join Early Testers"), destination: URL(string: "https://noemaai.com/early-testers")!)
        Text(LocalizedStringKey("Help shape Noema by trying upcoming features and sharing feedback."))
            .font(FontTheme.caption)
            .foregroundStyle(AppTheme.secondaryText)
    }

    // Provides iOS-only swipe actions while doing nothing on macOS
    private struct EmbeddingSwipeModifier: ViewModifier {
        let embedAvailable: Bool
        let onDelete: () -> Void

        func body(content: Content) -> some View {
#if os(iOS)
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if embedAvailable {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
#else
            content
#endif
        }
    }

    // System prompt section fully removed


    // Title section removed

    private var privacySection: some View {
        Section(LocalizedStringKey("Privacy")) { privacyContent }
    }

    @ViewBuilder
    private var privacyContent: some View {
        Button(LocalizedStringKey("Delete All Chats")) {
            triggerImpact(.medium)
            confirmClearChats = true
        }
        .tint(.red)
        Button(LocalizedStringKey("Reset App Data")) {
            triggerImpact(.medium)
            confirmResetAppData = true
        }
        .tint(.red)
        .disabled(isResettingAppData)
    }

    private var aboutSection: some View {
        Section(LocalizedStringKey("About & Support")) { aboutContent }
    }

    @ViewBuilder
    private var aboutContent: some View {
        Link(LocalizedStringKey("Terms of Use"), destination: URL(string: "https://noemaai.com/terms")!)
        Link(LocalizedStringKey("Privacy Policy"), destination: URL(string: "https://noemaai.com/privacy")!)
        Link(LocalizedStringKey("Contact Support"), destination: URL(string: "mailto:noema.clientcare@gmail.com")!)
        if (Bundle.main.infoDictionary?["AppStoreID"] as? String).map({ !$0.isEmpty }) == true {
            Button(LocalizedStringKey("Write a Review")) {
                ReviewPrompter.shared.openWriteReviewPageIfAvailable()
            }
        }
        NavigationLink(LocalizedStringKey("Notes & Issues")) {
            DisclaimerView()
        }
    }

    private var llamaCppSection: some View {
        Section { llamaContent } footer: {
            Text(LocalizedStringKey("This app bundles llama.cpp; we keep this in sync with upstream b‑releases."))
        }
    }

    @ViewBuilder
    private var llamaContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Llama.cpp")
                .font(FontTheme.body)
                .fontWeight(.medium)
                .foregroundStyle(AppTheme.text)
            Text(LocalizedStringKey("Latest integrated release: \(llamaCppBuild)"))
                .font(FontTheme.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        HStack(spacing: 12) {
            Image("Noema")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Noema")
                    .font(FontTheme.body)
                    .fontWeight(.medium)
                    .foregroundStyle(AppTheme.text)
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "Version %@"),
                        appVersion
                    )
                )
                    .font(FontTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
        }
    }

    private var advancedSection: some View {
        Group {
            Section(LocalizedStringKey("Retrieval")) { advancedRetrievalContent }
            // MCPs section removed
        }
    }

    @ViewBuilder
    private var advancedRetrievalContent: some View {
        Stepper(value: $settings.ragMaxChunks, in: 1...8) {
            HStack(spacing: 8) {
                let chunksFormatter: NumberFormatter = {
                    let nf = NumberFormatter()
                    nf.locale = localizationManager.locale
                    nf.numberStyle = .decimal
                    return nf
                }()
                let chunkString = chunksFormatter.string(from: NSNumber(value: settings.ragMaxChunks)) ?? "\(settings.ragMaxChunks)"
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "Max Chunks: %@", locale: localizationManager.locale),
                        chunkString
                    )
                )
                Spacer()
                Button { showChunksInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedStringKey("What is Max Chunks?"))
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey("Similarity Threshold"))
                Button { showSimilarityInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedStringKey("What is Similarity Threshold?"))
                Spacer()
                Text(String(format: "%.2f", settings.ragMinScore))
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Slider(value: $settings.ragMinScore, in: 0...1)
            Text(LocalizedStringKey("Lower = more results (more noise). Higher = stricter matches."))
                .font(FontTheme.caption)
                .foregroundStyle(AppTheme.tertiaryText)
        }
    }


    // Auto-title explanation removed

    private var modeExplanation: LocalizedStringKey {
        settings.isAdvancedMode
            ? LocalizedStringKey("Advanced mode shows developer options and diagnostics.")
            : LocalizedStringKey("Simple mode hides advanced settings for a cleaner interface.")
    }
}

private extension SettingsView {
    var languageOptions: [(code: String, name: String)] {
        let displayLocale = Locale(identifier: localizationManager.locale.identifier)
        return LocalizationManager.supportedLanguages.map { code in
            let name = displayLocale.localizedString(forIdentifier: code)
                ?? displayLocale.localizedString(forLanguageCode: code)
                ?? Locale(identifier: code).localizedString(forLanguageCode: code)
                ?? code
            return (code, name.capitalized)
        }
    }

    var currentLanguageCode: String {
        let id = localizationManager.locale.identifier.lowercased()
        return LocalizationManager.supportedLanguages.first(where: { id.hasPrefix($0.lowercased()) }) ?? "en"
    }


    // Start embedding model download from Settings using the same installer as onboarding
    func startEmbeddingDownloadFromSettings() {
        Task { @MainActor in
            await embedInstaller.installIfNeeded()
            if embedInstaller.state == .ready {
                await EmbeddingModel.shared.warmUp()
            }
        }
    }

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
        refreshStartupPreferences()

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

private struct StartupRemoteRow: View {
    @Binding var selection: StartupPreferences.RemoteSelection
    let backend: RemoteBackend?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                Text(selection.backendName)
                    .font(.headline)
                Text(backendDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if canMoveUp { Button(LocalizedStringKey("Move Up"), action: moveUp) }
                if canMoveDown { Button(LocalizedStringKey("Move Down"), action: moveDown) }
                Button(role: .destructive, action: remove) {
                    Label(LocalizedStringKey("Remove"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(LocalizedStringKey("Startup remote options"))
            }
        }
        if let backend {
            if backend.cachedModels.isEmpty {
                Text(LocalizedStringKey("No models cached yet. Open the backend to refresh its catalog."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(LocalizedStringKey("Model"), selection: $selection.modelID) {
                    ForEach(backend.cachedModels, id: \.id) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                if backend.cachedModels.first(where: { $0.id == selection.modelID }) == nil && !selection.modelID.isEmpty {
                    Text(LocalizedStringKey("We'll try this saved identifier even though it's not in the latest catalog."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text(LocalizedStringKey("This backend is unavailable. Remove it or pick another option."))
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
    .padding(.vertical, 4)
        .onChange(of: backend?.name ?? "") { newName in
            guard !newName.isEmpty, selection.backendName != newName else { return }
            selection.backendName = newName
        }
        .onChange(of: selection.modelID) { newValue in
            guard !newValue.isEmpty else { return }
            if let backend, let model = backend.cachedModels.first(where: { $0.id == newValue }) {
                selection.modelName = model.name
                selection.relayRecordName = model.relayRecordName
            } else if selection.modelName.isEmpty {
                selection.modelName = newValue
            }
        }
    }

    private var backendDescription: String {
        if let backend {
            return backend.endpointType.displayName
        }
        return String(localized: "Backend removed")
    }
}

private enum ImpactStyle {
    case medium
    case heavy
}

@MainActor
private func triggerImpact(_ style: ImpactStyle) {
#if canImport(UIKit) && !os(visionOS)
    let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
    switch style {
    case .medium:
        feedbackStyle = .medium
    case .heavy:
        feedbackStyle = .heavy
    }
    Haptics.impact(feedbackStyle)
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
                    Text(LocalizedStringKey("App Memory Usage (estimated)"))
                    Text(String.localizedStringWithFormat(String(localized: "%@ of %@ budget"), usageText, capText))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onAppear { start() }
        .onDisappear { stop() }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { @MainActor in refresh() }
        }
#endif
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
        .environmentObject(GuidedWalkthroughManager())
        .environmentObject(LocalizationManager())
}
