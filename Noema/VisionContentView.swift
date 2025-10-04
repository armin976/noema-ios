#if os(visionOS)
import SwiftUI
import UIKit
import RollingThought

/// Hosts the main tabs on visionOS, mirroring the iOS `MainView` hierarchy so
/// both platforms stay in sync while letting the visionOS scene supply shared
/// model objects.
struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var tabRouter: TabRouter
    @EnvironmentObject private var chatVM: ChatVM
    @EnvironmentObject private var modelManager: AppModelManager
    @EnvironmentObject private var datasetManager: DatasetManager
    @EnvironmentObject private var downloadController: DownloadController
    @EnvironmentObject private var walkthrough: GuidedWalkthroughManager
    @AppStorage("offGrid") private var offGrid = false
    @AppStorage("visionVerticalPanelLayout") private var useVerticalPanelLayout = true
    @AppStorage("defaultModelPath") private var defaultModelPath = ""
    @AppStorage("storedPanelWindowActive") private var storedPanelWindowActive = false
    @State private var didAutoLoad = false
    @State private var storedPanelLaunchInFlight = false // Legacy flag kept for state compatibility; now mirrors pending reopen work items.
    @State private var storedPanelRefreshWorkItem: DispatchWorkItem?

    private let storedPanelPlacementDelay: TimeInterval = 0.2

    private let mainGuideSteps: Set<GuidedWalkthroughManager.Step> = [
        .chatIntro,
        .chatSidebar,
        .chatNewChat,
        .chatInput,
        .chatWebSearch,
        .storedIntro,
        .storedRecommend,
        .storedFormats,
        .storedDatasets,
        .exploreIntro,
        .exploreDatasets,
        .exploreImport,
        .exploreSwitchToModels,
        .exploreModelTypes,
        .exploreMLX,
        .exploreSLM,
        .settingsIntro,
        .settingsHighlights,
        .completed
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if useVerticalPanelLayout {
                    tabLayout(includeStored: false)
                } else {
                    tabLayout(includeStored: true)
                }
            }

            DownloadOverlay()
                .environmentObject(downloadController)
        }
        .onPreferenceChange(GuidedHighlightPreferenceKey.self) { anchors in
            walkthrough.updateAnchors(anchors)
        }
        // Global indexing banner across all tabs
        .overlay(alignment: .top) {
            IndexingNotificationView(datasetManager: datasetManager)
                .environmentObject(chatVM)
                .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 60 : 8)
        }
        // Global model loading notification across all tabs
        .overlay(alignment: .top) {
            ModelLoadingNotificationView(modelManager: modelManager, loadingTracker: chatVM.loadingProgressTracker)
                .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 120 : 68)
        }
        .overlay {
            GuidedWalkthroughOverlay(allowedSteps: mainGuideSteps)
                .environmentObject(walkthrough)
        }
        .sheet(isPresented: $downloadController.showPopup) {
            DownloadListPopup()
                .environmentObject(downloadController)
        }
        .task { await autoLoad() }
        .onAppear {
            modelManager.bind(datasetManager: datasetManager)
            downloadController.configure(modelManager: modelManager, datasetManager: datasetManager)
            datasetManager.bind(downloadController: downloadController)
            chatVM.modelManager = modelManager
            chatVM.datasetManager = datasetManager
            let sanitized = sanitizedSelection(tabRouter.selection)
            if sanitized != tabRouter.selection {
                tabRouter.selection = sanitized
            }
            if let keys = UserDefaults.standard.array(forKey: "RollingThought.Keys") as? [String] {
                for key in keys {
                    let storageKey = "RollingThought." + key
                    if let existing = chatVM.rollingThoughtViewModels[key] {
                        existing.loadState(forKey: storageKey)
                    } else {
                        let vm = RollingThoughtViewModel()
                        vm.loadState(forKey: storageKey)
                        chatVM.rollingThoughtViewModels[key] = vm
                    }
                }
            }
            updateStoredPanelWindow(forceRecreation: true)
        }
        .onChange(of: offGrid) { on in
            NetworkKillSwitch.setEnabled(on)
            let sanitized = sanitizedSelection(tabRouter.selection)
            if sanitized != tabRouter.selection {
                tabRouter.selection = sanitized
            }
        }
        .onChange(of: useVerticalPanelLayout) { _ in
            let sanitized = sanitizedSelection(tabRouter.selection)
            if sanitized != tabRouter.selection {
                tabRouter.selection = sanitized
            }
            updateStoredPanelWindow(forceRecreation: true)
        }
        .onChange(of: tabRouter.selection) { _, newValue in
            let sanitized = sanitizedSelection(newValue)
            if sanitized != newValue {
                tabRouter.selection = sanitized
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                let keys = Array(chatVM.rollingThoughtViewModels.keys)
                UserDefaults.standard.set(keys, forKey: "RollingThought.Keys")
                for (key, vm) in chatVM.rollingThoughtViewModels {
                    vm.saveState(forKey: "RollingThought." + key)
                }
            } else if phase == .active {
                updateStoredPanelWindow(forceRecreation: true)
            }
        }
        .onChange(of: storedPanelWindowActive) { _, isActive in
            storedPanelRefreshWorkItem?.cancel()
            storedPanelRefreshWorkItem = nil

            if isActive {
                storedPanelLaunchInFlight = false
            } else {
                storedPanelLaunchInFlight = false
                if useVerticalPanelLayout {
                    scheduleStoredPanelOpen()
                }
            }
        }
    }

    @ViewBuilder
    private func tabLayout(includeStored: Bool) -> some View {
        TabView(selection: $tabRouter.selection) {
            tabContent(for: .chat)
                .tag(MainTab.chat)
                .tabItem { Label(tabTitle(for: .chat), systemImage: tabSystemImage(for: .chat)) }

            if includeStored {
                tabContent(for: .stored)
                    .tag(MainTab.stored)
                    .tabItem { Label(tabTitle(for: .stored), systemImage: tabSystemImage(for: .stored)) }
            }

            if !offGrid {
                tabContent(for: .explore)
                    .tag(MainTab.explore)
                    .tabItem { Label(tabTitle(for: .explore), systemImage: tabSystemImage(for: .explore)) }
            }

            tabContent(for: .settings)
                .tag(MainTab.settings)
                .tabItem { Label(tabTitle(for: .settings), systemImage: tabSystemImage(for: .settings)) }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: MainTab) -> some View {
        switch tab {
        case .chat:
            ChatView()
                .environmentObject(chatVM)
                .environmentObject(modelManager)
                .environmentObject(datasetManager)
                .environmentObject(tabRouter)
                .environmentObject(downloadController)
                .environmentObject(walkthrough)
        case .stored:
            StoredView()
                .environmentObject(chatVM)
                .environmentObject(modelManager)
                .environmentObject(datasetManager)
                .environmentObject(tabRouter)
                .environmentObject(downloadController)
                .environmentObject(walkthrough)
        case .explore:
            ExploreContainerView()
                .environmentObject(chatVM)
                .environmentObject(modelManager)
                .environmentObject(datasetManager)
                .environmentObject(tabRouter)
                .environmentObject(downloadController)
                .environmentObject(walkthrough)
        case .settings:
            SettingsView()
                .environmentObject(chatVM)
                .environmentObject(modelManager)
                .environmentObject(datasetManager)
                .environmentObject(tabRouter)
                .environmentObject(downloadController)
                .environmentObject(walkthrough)
        }
    }

    private func tabTitle(for tab: MainTab) -> String {
        switch tab {
        case .chat:
            return "Chat"
        case .stored:
            return "Stored"
        case .explore:
            return "Explore"
        case .settings:
            return "Settings"
        }
    }

    private func tabSystemImage(for tab: MainTab) -> String {
        switch tab {
        case .chat:
            return "message.fill"
        case .stored:
            return "externaldrive"
        case .explore:
            return "safari"
        case .settings:
            return "gearshape"
        }
    }

    private func sanitizedSelection(_ proposed: MainTab) -> MainTab {
        if useVerticalPanelLayout && proposed == .stored {
            return .chat
        }
        if offGrid && proposed == .explore {
            return .chat
        }
        return proposed
    }

    private func updateStoredPanelWindow(forceRecreation: Bool = false) {
        storedPanelRefreshWorkItem?.cancel()
        storedPanelLaunchInFlight = false

        guard useVerticalPanelLayout else {
            dismissWindow(id: VisionSceneID.storedPanelWindow)
            return
        }

        if storedPanelWindowActive {
            if forceRecreation {
                dismissWindow(id: VisionSceneID.storedPanelWindow)
                scheduleStoredPanelOpen(after: storedPanelPlacementDelay)
            }
            return
        }

        scheduleStoredPanelOpen()
    }

    private func scheduleStoredPanelOpen(after delay: TimeInterval? = nil) {
        storedPanelRefreshWorkItem?.cancel()
        storedPanelLaunchInFlight = false

        let reopen = DispatchWorkItem {
            openWindow(id: VisionSceneID.storedPanelWindow)
            storedPanelRefreshWorkItem = nil
            storedPanelLaunchInFlight = false
        }
        storedPanelRefreshWorkItem = reopen
        storedPanelLaunchInFlight = true
        let openDelay = delay ?? storedPanelPlacementDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + openDelay, execute: reopen)
    }

    @MainActor
    private func autoLoad() async {
        guard !didAutoLoad else { return }
        didAutoLoad = true

        if UserDefaults.standard.bool(forKey: "bypassRAMLoadPending") {
            UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
            modelManager.refresh()
            chatVM.loadError = "Previous model failed to load because it likely exceeded memory. Lower context size or choose a smaller model."
            return
        }

        guard !chatVM.modelLoaded, !chatVM.loading else { return }
        modelManager.refresh()

        guard !defaultModelPath.isEmpty,
              let model = modelManager.downloadedModels.first(where: { $0.url.path == defaultModelPath }) else { return }

        let settings = modelManager.settings(for: model)
        UserDefaults.standard.set(true, forKey: "bypassRAMLoadPending")
        await chatVM.unload()
        if await chatVM.load(url: model.url, settings: settings, format: model.format) {
            modelManager.updateSettings(settings, for: model)
            modelManager.markModelUsed(model)
        } else {
            modelManager.loadedModel = nil
        }
        UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
    }
}

/// Vision-specific wrapper around the shared tab hierarchy. The iOS
/// implementation owns its view models via `@StateObject`, while the visionOS
/// scene receives them from the app entry point so they can also drive the
/// immersive space. This view therefore observes the supplied objects without
/// taking ownership.
struct ContentView: View {
    private let mode: VisionWindowMode
    @ObservedObject private var tabRouter: TabRouter
    @ObservedObject private var chatVM: ChatVM
    @ObservedObject private var modelManager: AppModelManager
    @ObservedObject private var datasetManager: DatasetManager
    @ObservedObject private var downloadController: DownloadController
    @ObservedObject private var walkthroughManager: GuidedWalkthroughManager

    @State private var showSplash: Bool
    @State private var showOnboarding = false
    @State private var didConfigure = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init(
        mode: VisionWindowMode,
        tabRouter: TabRouter,
        chatVM: ChatVM,
        modelManager: AppModelManager,
        datasetManager: DatasetManager,
        downloadController: DownloadController,
        walkthroughManager: GuidedWalkthroughManager
    ) {
        self.mode = mode
        _showSplash = State(initialValue: mode == .planar)
        _tabRouter = ObservedObject(wrappedValue: tabRouter)
        _chatVM = ObservedObject(wrappedValue: chatVM)
        _modelManager = ObservedObject(wrappedValue: modelManager)
        _datasetManager = ObservedObject(wrappedValue: datasetManager)
        _downloadController = ObservedObject(wrappedValue: downloadController)
        _walkthroughManager = ObservedObject(wrappedValue: walkthroughManager)
    }

    var body: some View {
        ZStack {
            MainView()
                .environmentObject(tabRouter)
                .environmentObject(chatVM)
                .environmentObject(modelManager)
                .environmentObject(datasetManager)
                .environmentObject(downloadController)
                .environmentObject(walkthroughManager)
                .glassBackgroundEffect()

            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { mode == .planar && showOnboarding },
                set: { showOnboarding = $0 }
            )
        ) {
            OnboardingView(showOnboarding: $showOnboarding)
                .environmentObject(tabRouter)
                .environmentObject(chatVM)
                .environmentObject(modelManager)
                .environmentObject(datasetManager)
                .environmentObject(downloadController)
                .environmentObject(walkthroughManager)
        }
        .onAppear(perform: configureOnce)
    }

    private func configureOnce() {
        guard !didConfigure else { return }
        didConfigure = true
        walkthroughManager.configure(tabRouter: tabRouter,
                                      chatVM: chatVM,
                                      modelManager: modelManager,
                                      datasetManager: datasetManager,
                                      downloadController: downloadController)

        guard mode == .planar else {
            showSplash = false
            return
        }
        print("[Noema] visionOS app launched 🚀")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showSplash = false
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
        }
    }
}

/// Splash screen used on visionOS to mirror the iOS experience.
private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image("Noema")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }
}

struct StoredPanelWindow: View {
    @AppStorage("storedPanelWindowActive") private var storedPanelWindowActive = false

    var body: some View {
        VisionStoredPanel()
            .frame(width: 420)
            .glassBackgroundEffect()
            .onAppear { storedPanelWindowActive = true }
            .onDisappear { storedPanelWindowActive = false }
    }
}

#endif
