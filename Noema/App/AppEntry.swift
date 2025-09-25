import SwiftUI

@main
struct NoemaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appEnvironment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            MainShell()
                .environmentObject(appEnvironment.experience)
                .environmentObject(appEnvironment.chatVM)
                .environmentObject(appEnvironment.modelManager)
                .environmentObject(appEnvironment.datasetManager)
                .environmentObject(appEnvironment.downloadController)
                .environmentObject(appEnvironment.tabRouter)
                .environmentObject(appEnvironment.inspectorController)
                .preferredColorScheme(appEnvironment.preferredColorScheme)
        }
        .commands {
            KeyboardShortcutCommands(experience: appEnvironment.experience)
            InspectorCommands(inspectorController: appEnvironment.inspectorController)
#if DEBUG
            DebugCommands(inspectorController: appEnvironment.inspectorController)
#endif
        }
    }
}
