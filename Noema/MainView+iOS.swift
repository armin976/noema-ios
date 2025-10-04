import SwiftUI
import RollingThought

#if !os(visionOS)
typealias ChatView = MessageView.ChatView

/// Hosts the main tabs with the default system tab bar.
struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var tabRouter: TabRouter
    @EnvironmentObject private var chatVM: ChatVM
    @EnvironmentObject private var modelManager: AppModelManager
    @EnvironmentObject private var datasetManager: DatasetManager
    @EnvironmentObject private var downloadController: DownloadController
    @EnvironmentObject private var walkthrough: GuidedWalkthroughManager
    @AppStorage("offGrid") private var offGrid = false
    @AppStorage("defaultModelPath") private var defaultModelPath = ""
    @State private var didAutoLoad = false

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
            TabView(selection: $tabRouter.selection) {
                ChatView()
                    .tag(MainTab.chat)
                    .environmentObject(chatVM)
                    .environmentObject(modelManager)
                    .environmentObject(datasetManager)
                    .environmentObject(tabRouter)
                    .environmentObject(downloadController)
                    .environmentObject(walkthrough)
                    .tabItem { Label("Chat", systemImage: "message.fill") }

                StoredView()
                    .tag(MainTab.stored)
                    .environmentObject(chatVM)
                    .environmentObject(modelManager)
                    .environmentObject(datasetManager)
                    .environmentObject(tabRouter)
                    .environmentObject(downloadController)
                    .environmentObject(walkthrough)
                    .tabItem { Label("Stored", systemImage: "externaldrive") }

                if !offGrid {
                    ExploreContainerView()
                        .tag(MainTab.explore)
                        .environmentObject(chatVM)
                        .environmentObject(modelManager)
                        .environmentObject(datasetManager)
                        .environmentObject(tabRouter)
                        .environmentObject(downloadController)
                        .environmentObject(walkthrough)
                        .tabItem { Label("Explore", systemImage: "safari") }
                }

                SettingsView()
                    .tag(MainTab.settings)
                    .environmentObject(chatVM)
                    .environmentObject(modelManager)
                    .environmentObject(datasetManager)
                    .environmentObject(tabRouter)
                    .environmentObject(downloadController)
                    .environmentObject(walkthrough)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
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
                .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 120 : 68)  // Offset below indexing notification
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
            // Don't automatically initialize embedding model or select datasets
            // User must explicitly choose to use a dataset
            // Load persisted rolling thought boxes, if any
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
        }
        .onChange(of: offGrid) { on in
            NetworkKillSwitch.setEnabled(on)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                // Persist all rolling thought boxes for restoration on next launch
                let keys = Array(chatVM.rollingThoughtViewModels.keys)
                UserDefaults.standard.set(keys, forKey: "RollingThought.Keys")
                for (key, vm) in chatVM.rollingThoughtViewModels {
                    vm.saveState(forKey: "RollingThought." + key)
                }
            }
        }
    }

    @MainActor
    private func autoLoad() async {
        guard !didAutoLoad else { return }
        didAutoLoad = true

        // If a previous bypassed load crashed the app, skip autoload and inform the user
        if UserDefaults.standard.bool(forKey: "bypassRAMLoadPending") {
            UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
            modelManager.refresh()
            chatVM.loadError = "Previous model failed to load because it likely exceeded memory. Lower context size or choose a smaller model."
            return
        }

        guard !chatVM.modelLoaded, !chatVM.loading else { return }
        modelManager.refresh()
        // Only autoload when a default model path is explicitly set
        guard !defaultModelPath.isEmpty,
              let model = modelManager.downloadedModels.first(where: { $0.url.path == defaultModelPath }) else { return }

        let settings = modelManager.settings(for: model)
        // Mark pending so if the app crashes during autoload, we won't autoload on next launch
        UserDefaults.standard.set(true, forKey: "bypassRAMLoadPending")
        await chatVM.unload()
        if await chatVM.load(url: model.url, settings: settings, format: model.format) {
            modelManager.updateSettings(settings, for: model)
            modelManager.markModelUsed(model)
        } else {
            modelManager.loadedModel = nil
        }
        // Clear pending flag if we survived the load attempt
        UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
    }
}
#endif
