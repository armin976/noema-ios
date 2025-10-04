import SwiftUI
import UIKit

#if canImport(FBSDKCoreKit) && os(iOS)
import FBSDKCoreKit
#endif

#if os(visionOS)

@main
struct NoemaVisionOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        configureSharedApplicationEnvironment()
    }

    var body: some Scene {
        NoemaVisionMainScene()
    }
}

#else

@main
struct NoemaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage("appearance") private var appearance = "system"

#if canImport(FBSDKCoreKit) && os(iOS)
    @Environment(\.scenePhase) private var scenePhase
#endif

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    init() {
        configureSharedApplicationEnvironment()
    }

    var body: some Scene {
        WindowGroup {
            ContentView().preferredColorScheme(colorScheme)
#if canImport(FBSDKCoreKit) && os(iOS)
                .onAppear {
                    AppEvents.shared.activateApp()
                }
#endif
        }
#if canImport(FBSDKCoreKit) && os(iOS)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                AppEvents.shared.activateApp()
            }
        }
#endif
    }
}

#endif
