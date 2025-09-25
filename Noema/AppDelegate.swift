import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UserDefaults.standard.register(defaults: [
            "console.maxHistoryLines": 300,
            "console.autoOpenOnRun": true
        ])
        BackgroundDownloadManager.shared.scheduleMaintenance()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        BackgroundDownloadManager.shared.handleEvents(for: identifier, completionHandler: completionHandler)
    }
}
