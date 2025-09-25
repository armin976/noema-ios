import SwiftUI

/// Provides keyboard shortcuts and menu commands for the Inspector panel.
struct InspectorCommands: Commands {
    @ObservedObject var inspectorController: InspectorController
    @AppStorage("inspectorEnabled") private var inspectorEnabled = false

    var body: some Commands {
        if inspectorEnabled {
            CommandMenu("Inspector") {
                Button(inspectorController.isPresented ? "Hide Inspector" : "Show Inspector") {
                    inspectorController.toggle()
                }
                .keyboardShortcut(";", modifiers: [.command])
            }
        }
    }
}

#if DEBUG
/// Items that integrate the Inspector toggle into the existing Debug menu.
struct InspectorDebugMenuItems: View {
    @ObservedObject var inspectorController: InspectorController
    @AppStorage("inspectorEnabled") private var inspectorEnabled = false

    var body: some View {
        if inspectorEnabled {
            Divider()
            Button(inspectorController.isPresented ? "Hide Inspector" : "Show Inspector") {
                inspectorController.toggle()
            }
        }
    }
}
#endif
