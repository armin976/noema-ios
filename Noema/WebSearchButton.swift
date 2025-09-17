// WebSearchButton.swift
import SwiftUI

struct WebSearchButton: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var usageTracker = SearchUsageTracker.shared
    let size: CGFloat = 28
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var datasetManager: DatasetManager
    @State private var showLimitAlert = false
    @State private var showUpgradeSheet = false
    @State private var supportsFunctionCalling = (UserDefaults.standard.object(forKey: "currentModelSupportsFunctionCalling") as? Bool ?? false)
    @State private var showDisabledReason = false
    @AppStorage("hasSeenWebSearchNotice") private var hasSeenWebSearchNotice = false
    @State private var showWebSearchNotice = false

    var body: some View {
        Button(action: toggle) {
            Image(systemName: iconName)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(fgColor)
                .padding(10)
                .background(
                    Circle()
                        .fill(bgFill)
                        .overlay(
                            Circle()
                                .strokeBorder(borderColor, lineWidth: settings.webSearchArmed ? 1.0 : 0.5)
                        )
                        .shadow(color: glowColor, radius: settings.webSearchArmed ? 8 : 0)
                )
                .accessibilityLabel("Web Search")
                .accessibilityHint(accessibilityHint)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: settings.webSearchArmed)
        .help(helpText)
        // Capture taps even when visually disabled to explain why it is disabled
        .overlay(
            Color.clear
                .contentShape(Circle())
                .onTapGesture {
                    if isDisabled { showDisabledReason = true }
                }
                .allowsHitTesting(isDisabled)
        )
        .alert("Search Limit Reached", isPresented: $showLimitAlert) {
            Button("Upgrade", action: { 
                guard !showUpgradeSheet else { return }
                showUpgradeSheet = true 
            })
            Button("OK", role: .cancel) { }
        } message: {
            Text("You've reached your daily limit of 5 searches. \(usageTracker.timeUntilReset())")
        }
        .alert("Web Search Unavailable", isPresented: $showDisabledReason) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(disabledReason)
        }
        .alert("Tool Calling", isPresented: $showWebSearchNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tool calling isn't perfect. Although Noema implements many methods of detecting and instructing models to use tools, not all LLMs will follow instructions and some might not call them correctly or at all. Tool calling heavily depends on model pre-training and will get better as time passes.")
        }
        .sheet(isPresented: $showUpgradeSheet) {
            UpgradeView()
        }
        .onChange(of: datasetActive) { _, active in
            if active && settings.webSearchArmed { settings.webSearchArmed = false }
        }
        .onChange(of: supportsFunctionCalling) { _, supported in
            if !supported && settings.webSearchArmed { settings.webSearchArmed = false }
        }
        .onChange(of: vm.isSLMModel) { _, isSLM in
            if isSLM && settings.webSearchArmed { settings.webSearchArmed = false }
        }
        .onChange(of: usageTracker.limitReached) { _, reached in
            // When the daily limit is reached for non‑subscribers, auto‑disarm
            if reached && !settings.hasUnlimitedSearches && settings.webSearchArmed {
                settings.webSearchArmed = false
            }
        }
        .onAppear {
            if datasetActive && settings.webSearchArmed { settings.webSearchArmed = false }
            // Also disarm on appear if user has hit the limit and is not subscribed
            if !settings.hasUnlimitedSearches && usageTracker.limitReached && settings.webSearchArmed {
                settings.webSearchArmed = false
            }
            supportsFunctionCalling = (UserDefaults.standard.object(forKey: "currentModelSupportsFunctionCalling") as? Bool ?? false)
            if vm.isSLMModel && settings.webSearchArmed { settings.webSearchArmed = false }
        }
    }

    private var datasetActive: Bool {
        if let ds = modelManager.activeDataset { return true }
        if datasetManager.indexingDatasetID != nil { return true }
        return false
    }

    private var hasRecentWebSearch: Bool {
        // Check if the current or recent message has a web search
        if let lastMsg = vm.msgs.last(where: { $0.role == "🤖" || $0.role.lowercased() == "assistant" }) {
            return lastMsg.usedWebSearch == true || lastMsg.webHits != nil
        }
        return false
    }

    private var iconName: String {
        // Don't show exclamation if we just performed a successful search
        if hasRecentWebSearch {
            return "globe"
        }
        if isLimitReached && settings.webSearchArmed {
            return "exclamationmark.circle"
        }
        return "globe"
    }

    private var isLimitReached: Bool {
        !settings.hasUnlimitedSearches && usageTracker.limitReached
    }

    private var isDisabled: Bool {
        // Disable while dataset is in use (selected or indexing), or off-grid, or globally disabled
        let offGrid = UserDefaults.standard.object(forKey: "offGrid") as? Bool ?? false
        // Also disable if current model does not support function calling (model card check)
        let supportedFlag = (UserDefaults.standard.object(forKey: "currentModelSupportsFunctionCalling") as? Bool ?? false)
        if vm.isSLMModel { return true }
        let supported = supportedFlag
        // Disable when daily limit reached for non‑subscribers
        let limitDisabled = !settings.hasUnlimitedSearches && usageTracker.limitReached
        return offGrid || !settings.webSearchEnabled || datasetActive || !supported || limitDisabled
    }
    private var disabledReason: String {
        let offGrid = UserDefaults.standard.object(forKey: "offGrid") as? Bool ?? false
        let supported = (UserDefaults.standard.object(forKey: "currentModelSupportsFunctionCalling") as? Bool ?? false)
        if !settings.hasUnlimitedSearches && usageTracker.limitReached {
            return "Daily web search limit reached (5/5). Upgrade for unlimited searches or wait for reset."
        }
        if vm.isSLMModel {
            return "Web Search isn’t supported for this model yet."
        }
        if !supported {
            return "This model does not support function calling; web search requires it."
        }
        if datasetActive {
            return "Web search can’t be used while a dataset is active or indexing."
        }
        if offGrid {
            return "Off‑Grid mode is on. Network features like web search are disabled."
        }
        if !settings.webSearchEnabled {
            return "Web Search is turned off in Settings."
        }
        return "Web Search is currently unavailable."
    }
    private var fgColor: Color { 
        if isDisabled { return .secondary }
        // Don't show orange if we just performed a search
        if isLimitReached && settings.webSearchArmed && !hasRecentWebSearch { return .orange }
        return .primary
    }
    private var bgFill: Color { isDisabled ? Color.gray.opacity(0.12) : Color(.systemBackground) }
    private var borderColor: Color { 
        // Don't show orange if we just performed a search
        if isLimitReached && settings.webSearchArmed && !hasRecentWebSearch { return Color.orange.opacity(0.6) }
        return settings.webSearchArmed ? Color.blue.opacity(0.6) : Color.gray.opacity(0.25) 
    }
    private var glowColor: Color { 
        // Don't show orange if we just performed a search
        if isLimitReached && settings.webSearchArmed && !hasRecentWebSearch { return Color.orange.opacity(0.55) }
        return settings.webSearchArmed ? Color.blue.opacity(0.55) : .clear 
    }
    private var accessibilityHint: String { 
        if isDisabled {
            if vm.isSLMModel { return "Disabled: web search isn’t available for this model yet" }
            let supported = (UserDefaults.standard.object(forKey: "currentModelSupportsFunctionCalling") as? Bool ?? false)
            if !supported { return "Disabled: model lacks function calling support" }
            return "Disabled while using a dataset"
        }
        if isLimitReached && settings.webSearchArmed && !hasRecentWebSearch { return "Limit reached" }
        return settings.webSearchArmed ? "On" : "Off"
    }

    private var helpText: String {
        // Brief guidance shown as a tooltip on macOS/iPadOS pointer hover
        let supportsFunctionCalling = UserDefaults.standard.object(forKey: "currentModelSupportsFunctionCalling") as? Bool ?? false
        if vm.isSLMModel { return "Leap SLM models can’t use web search yet." }
        if !supportsFunctionCalling {
            return "This model does not advertise function calling support in its model card; web search is disabled."
        }
        return "Toggle web search tool. Uses Brave Search. Requires models with function calling support."
    }

    private func toggle() {
        guard !isDisabled else { return }

        // If turning on and limit reached, show alert instead
        if !settings.webSearchArmed && isLimitReached {
            showLimitAlert = true
            return
        }

        let newValue = !settings.webSearchArmed
        settings.webSearchArmed = newValue
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if newValue && !hasSeenWebSearchNotice {
            hasSeenWebSearchNotice = true
            showWebSearchNotice = true
        }
    }
}
