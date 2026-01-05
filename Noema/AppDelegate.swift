#if canImport(UIKit)
import UIKit

#if canImport(FBSDKCoreKit) && os(iOS)
import FBSDKCoreKit
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
#if canImport(FBSDKCoreKit) && os(iOS)
        let handled = ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
#else
        let handled = true
#endif
        BackgroundDownloadManager.shared.scheduleMaintenance()
        return handled
    }

#if canImport(FBSDKCoreKit) && os(iOS)
    func applicationDidBecomeActive(_ application: UIApplication) {
        AppEvents.shared.activateApp()
    }
#endif

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        BackgroundDownloadManager.shared.handleEvents(for: identifier, completionHandler: completionHandler)
    }

#if canImport(FBSDKCoreKit) && os(iOS)
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        let handled = ApplicationDelegate.shared.application(app, open: url, options: options)
        return handled
    }
#endif
}
#endif
