import SwiftUI

#if !os(visionOS)
/// Root SwiftUI view for the iOS and iPadOS experience. It owns the shared
/// view models so they persist across the tab hierarchy and manages the launch
/// splash/onboarding flow.
struct ContentView: View {
    @State private var showSplash = true
    @State private var showOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var tabRouter: TabRouter
    @StateObject private var chatVM: ChatVM
    @StateObject private var modelManager: AppModelManager
    @StateObject private var datasetManager: DatasetManager
    @StateObject private var downloadController: DownloadController
    @StateObject private var walkthroughManager: GuidedWalkthroughManager

    init(
        tabRouter: TabRouter = TabRouter(),
        chatVM: ChatVM = ChatVM(),
        modelManager: AppModelManager = AppModelManager(),
        datasetManager: DatasetManager = DatasetManager(),
        downloadController: DownloadController = DownloadController(),
        walkthroughManager: GuidedWalkthroughManager = GuidedWalkthroughManager()
    ) {
        _tabRouter = StateObject(wrappedValue: tabRouter)
        _chatVM = StateObject(wrappedValue: chatVM)
        _modelManager = StateObject(wrappedValue: modelManager)
        _datasetManager = StateObject(wrappedValue: datasetManager)
        _downloadController = StateObject(wrappedValue: downloadController)
        _walkthroughManager = StateObject(wrappedValue: walkthroughManager)
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

            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(showOnboarding: $showOnboarding)
                .environmentObject(tabRouter)
                .environmentObject(chatVM)
                .environmentObject(modelManager)
                .environmentObject(datasetManager)
                .environmentObject(downloadController)
                .environmentObject(walkthroughManager)
        }
        .onAppear {
            print("[Noema] app launched 🚀")
            walkthroughManager.configure(tabRouter: tabRouter,
                                         chatVM: chatVM,
                                         modelManager: modelManager,
                                         datasetManager: datasetManager,
                                         downloadController: downloadController)
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
}

private struct IndexingBannerContainer: View {
    @EnvironmentObject var chatVM: ChatVM
    @EnvironmentObject var datasetManager: DatasetManager
    var body: some View {
        VStack {
            IndexingNotificationView(datasetManager: datasetManager)
                .environmentObject(chatVM)
                .padding(.top, 12)
            Spacer()
        }
        .allowsHitTesting(true)
    }
}

/// Splash screen shown at launch with the app logo and a spinner.
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
#endif
