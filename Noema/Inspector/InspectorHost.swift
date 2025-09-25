import SwiftUI

/// Coordinates presentation of the Inspector panel from anywhere in the app.
@MainActor
final class InspectorController: ObservableObject {
    @Published var isPresented = false

    func present() { isPresented = true }
    func dismiss() { isPresented = false }
    func toggle() { isPresented.toggle() }
}

/// Hosts the Inspector UI in a trailing side panel.
struct InspectorHost: View {
    @ObservedObject var controller: InspectorController
    @EnvironmentObject private var tabRouter: TabRouter

    @AppStorage("inspector.lastTab.chat") private var chatLastTabRaw = InspectorPanel.Tab.artifacts.rawValue
    @AppStorage("inspector.lastTab.stored") private var storedLastTabRaw = InspectorPanel.Tab.artifacts.rawValue
    @AppStorage("inspector.lastTab.explore") private var exploreLastTabRaw = InspectorPanel.Tab.artifacts.rawValue
    @AppStorage("inspector.lastTab.settings") private var settingsLastTabRaw = InspectorPanel.Tab.artifacts.rawValue

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            InspectorPanel(selection: bindingForCurrentSpace())
        }
        .frame(width: 360)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 16, x: -4, y: 0)
        .padding(.vertical, 24)
        .padding(.trailing, 16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Inspector")
                    .font(.headline)
                Text(tabTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                controller.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Inspector")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var tabTitle: String {
        switch tabRouter.selection {
        case .chat: return "Chat"
        case .stored: return "Stored"
        case .explore: return "Explore"
        case .settings: return "Settings"
        }
    }

    private func bindingForCurrentSpace() -> Binding<InspectorPanel.Tab> {
        Binding(
            get: {
                let raw: String
                switch tabRouter.selection {
                case .chat: raw = chatLastTabRaw
                case .stored: raw = storedLastTabRaw
                case .explore: raw = exploreLastTabRaw
                case .settings: raw = settingsLastTabRaw
                }
                return InspectorPanel.Tab(rawValue: raw) ?? .artifacts
            },
            set: { newValue in
                let raw = newValue.rawValue
                switch tabRouter.selection {
                case .chat: chatLastTabRaw = raw
                case .stored: storedLastTabRaw = raw
                case .explore: exploreLastTabRaw = raw
                case .settings: settingsLastTabRaw = raw
                }
            }
        )
    }
}
