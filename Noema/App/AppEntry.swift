import SwiftUI

@main
struct NoemaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appEnvironment = AppEnvironment()
    private var inspectorController: InspectorController { appEnvironment.inspectorController }

    var body: some Scene {
        WindowGroup {
            MainShell()
                .environmentObject(appEnvironment.experience)
                .environmentObject(appEnvironment.chatVM)
                .environmentObject(appEnvironment.modelManager)
                .environmentObject(appEnvironment.datasetManager)
                .environmentObject(appEnvironment.downloadController)
                .environmentObject(appEnvironment.tabRouter)
                .environmentObject(inspectorController)
                .preferredColorScheme(appEnvironment.preferredColorScheme)
        }
        .commands {
            KeyboardShortcutCommands(experience: appEnvironment.experience)
            InspectorCommands(inspectorController: inspectorController)
#if DEBUG
            DebugCommands(inspectorController: inspectorController)
#endif
        }
    }
}
