import SwiftUI
import NoemaCore

private struct ShortcutInfo: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let key: String
}

private struct ShortcutSection: Identifiable {
    let id = UUID()
    let title: String
    let shortcuts: [ShortcutInfo]
}

struct KeyboardShortcutCheatSheetView: View {
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let sections: [ShortcutSection] = [
        ShortcutSection(
            title: "Chat",
            shortcuts: [
                ShortcutInfo(title: "New chat", detail: "Start a fresh conversation.", key: "⌘N"),
                ShortcutInfo(title: "Send message", detail: "Send the text currently in the composer.", key: "⌘↩︎"),
                ShortcutInfo(title: "Stop response", detail: "Cancel the active generation.", key: "⌘."),
                ShortcutInfo(title: "Focus composer", detail: "Move focus to the message input field.", key: "⌘K")
            ]
        ),
        ShortcutSection(
            title: "Navigation",
            shortcuts: [
                ShortcutInfo(title: "Keyboard cheat sheet", detail: "Show this list of shortcuts.", key: "⌘?")
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.shortcuts) { ShortcutRow(shortcut: $0) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Keyboard Shortcuts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
    }
}

private struct ShortcutRow: View {
    let shortcut: ShortcutInfo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.title)
                    .font(.body.weight(.semibold))
                Text(shortcut.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(shortcut.key)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(shortcut.title), \(shortcut.key)")
        .accessibilityHint(shortcut.detail)
    }
}

final class SettingsModel: ObservableObject {
    @AppStorage("offGrid") var offGrid = false
    @AppStorage("appearance") var appearance = "system"
    @AppStorage("defaultModelPath") var defaultModelPath = ""
    @AppStorage("verboseLogging") var verboseLogging = false
    @AppStorage("bypassRAMCheck") var bypassRAMCheck = false
    @AppStorage("ragMaxChunks") var ragMaxChunks = 5
    @AppStorage("ragMinScore") var ragMinScore: Double = 0.5
    @AppStorage("pythonEnabled") var pythonEnabled = true {
        didSet {
            NotificationCenter.default.post(name: .pythonSettingsDidChange, object: pythonEnabled)
        }
    }
    @AppStorage("showMultimodalUI") var showMultimodalUI = false

    func resetAppData() {
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
    }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsModel()
    @EnvironmentObject private var modelManager: AppModelManager
    @State private var showAdvanced = false
    @State private var showResetConfirmation = false
    @State private var showCacheConfirmation = false
    @State private var showCacheSuccess = false
    @State private var errorMessage: String?
    @State private var isClearingCache = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    appearancePicker
                    defaultModelPicker
                    offlineToggle
                    clearCacheButton
                    aboutLink
                    resetButton
                }
                .listRowBackground(Tokens.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.Colors.background.ignoresSafeArea())
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdvanced = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .a11yLabel("Advanced settings")
                    .a11yTarget()
                }
            }
            .sheet(isPresented: $showAdvanced) {
                AdvancedSheet(settings: settings)
            }
            .onAppear(perform: validateDefaultModel)
            .onReceive(modelManager.$downloadedModels) { _ in
                validateDefaultModel()
            }
            .alert("Cache Cleared", isPresented: $showCacheSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Python notebook cache has been cleared.")
            }
            .alert("Reset Settings?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    settings.resetAppData()
                }
            } message: {
                Text("Restores default preferences and clears saved accounts.")
            }
            .alert("Clear Cache?", isPresented: $showCacheConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    clearCache()
                }
            } message: {
                Text("Removes cached notebook runs and artifacts.")
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var appearancePicker: some View {
        Picker("Appearance", selection: $settings.appearance) {
            Text("System").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
        }
        .pickerStyle(.navigationLink)
        .font(Tokens.Typography.body)
        .a11yTarget()
    }

    private var defaultModelPicker: some View {
        Picker("Default model", selection: $settings.defaultModelPath) {
            Text("None").tag("")
            ForEach(modelManager.downloadedModels, id: \.url) { model in
                Text(model.name).tag(model.url.path)
            }
        }
        .pickerStyle(.navigationLink)
        .font(Tokens.Typography.body)
        .onChange(of: settings.defaultModelPath) { _, newValue in
            guard !newValue.isEmpty else { return }
            if !modelManager.downloadedModels.contains(where: { $0.url.path == newValue }) {
                settings.defaultModelPath = ""
            }
        }
        .a11yTarget()
    }

    private var offlineToggle: some View {
        Toggle("Offline mode", isOn: $settings.offGrid)
            .onChange(of: settings.offGrid) { on in
                NetworkKillSwitch.setEnabled(on)
            }
            .toggleStyle(.switch)
            .font(Tokens.Typography.body)
            .a11yLabel("Offline mode")
            .a11yTarget()
    }

    private var clearCacheButton: some View {
        Button {
            showCacheConfirmation = true
        } label: {
            HStack {
                Label("Clear Python cache", systemImage: "trash")
                    .font(Tokens.Typography.body)
                if isClearingCache {
                    Spacer(minLength: Tokens.Spacing.medium)
                    ProgressView()
                }
            }
        }
        .disabled(isClearingCache)
        .tint(Tokens.Colors.danger)
        .a11yLabel("Clear Python cache")
        .a11yHint("Deletes cached notebook results.")
        .a11yTarget()
    }

    private var aboutLink: some View {
        NavigationLink {
            AboutPane()
        } label: {
            Label("About & support", systemImage: "info.circle")
                .font(Tokens.Typography.body)
        }
        .a11yLabel("About and support")
        .a11yTarget()
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            showResetConfirmation = true
        } label: {
            Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                .font(Tokens.Typography.body)
        }
        .a11yLabel("Reset settings to defaults")
        .a11yTarget()
    }

    private func clearCache() {
        guard !isClearingCache else { return }
        isClearingCache = true
        Task(priority: .userInitiated) {
            do {
                try PythonResultCache.shared.clear()
                await MainActor {
                    isClearingCache = false
                    showCacheSuccess = true
                }
            } catch let appError as AppError {
                await present(error: appError)
            } catch {
                let wrapped = AppError(code: .unknown, message: error.localizedDescription)
                await present(error: wrapped)
            }
        }
    }

    @MainActor
    private func present(error: AppError) {
        isClearingCache = false
        errorMessage = ErrorPresenter.present(error)
    }

    private func validateDefaultModel() {
        guard !settings.defaultModelPath.isEmpty else { return }
        if !modelManager.downloadedModels.contains(where: { $0.url.path == settings.defaultModelPath }) {
            settings.defaultModelPath = ""
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        List {
            Section {
                SettingsRow(title: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—", icon: "number")
                Link(destination: URL(string: "https://noemaai.com/privacy")!) {
                    SettingsRow(title: "Privacy policy", icon: "lock.shield")
                }
                Link(destination: URL(string: "mailto:noema.clientcare@gmail.com")!) {
                    SettingsRow(title: "Contact support", icon: "envelope")
                }
                NavigationLink {
                    DisclaimerView()
                } label: {
                    SettingsRow(title: "Notes & issues", icon: "doc.text")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.Colors.background.ignoresSafeArea())
        .listStyle(.insetGrouped)
        .navigationTitle("About")
    }
}

private struct SettingsRow: View {
    let title: String
    var value: String?
    var icon: String

    var body: some View {
        HStack(spacing: Tokens.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Tokens.Colors.accent)
                .frame(width: 28)
            Text(title)
                .font(Tokens.Typography.body)
            Spacer()
            if let value {
                Text(value)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Tokens.Spacing.small)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ChatVM())
        .environmentObject(AppModelManager())
}
