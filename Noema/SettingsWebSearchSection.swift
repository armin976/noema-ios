// SettingsWebSearchSection.swift
import SwiftUI

struct SettingsWebSearchSection: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var usageTracker = SearchUsageTracker.shared
    @State private var showInfo = false
    @State private var now = Date()
    @Binding var showUpgradeSheet: Bool

    var body: some View {
        Section(header: Text("Search")) {
            Toggle(isOn: $settings.webSearchEnabled) {
                HStack(spacing: 8) {
                    Text("Web Search button")
                    Button { showInfo = true } label: {
                        Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("What is Web Search button?")
                }
            }
            .onChange(of: settings.webSearchEnabled) { _, on in
                if !on { settings.webSearchArmed = false }
            }
            .tint(.blue)
            
            // Usage display
            if settings.webSearchEnabled {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily Usage")
                            .font(.subheadline)
                        if settings.hasUnlimitedSearches {
                            Label("Unlimited searches", systemImage: "infinity.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text(usageTracker.usageText)
                                .font(.caption)
                                .foregroundStyle(usageTracker.limitReached ? .orange : .secondary)
                            // Always show time until the next daily reset beneath the usage text
                            Text(timeUntilReset(from: now))
                                .font(.caption2)
                                .foregroundStyle(usageTracker.limitReached ? .orange : .secondary)
                        }
                    }
                    Spacer()
                    if !settings.hasUnlimitedSearches {
                        Button("Upgrade") {
                            guard !showUpgradeSheet else { return }
                            showUpgradeSheet = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
                .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { t in
                    now = t
                }
            }
        }
        .alert("Web Search button", isPresented: $showInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Allows models to use a local, privacy-preserving web search tool when you tap the globe in chat. Default is ON. In Offline Only mode, the button is disabled.")
        }
        // Sheet is presented by the parent view to avoid premature dismissal
    }
}


// MARK: - Helpers
private extension SettingsWebSearchSection {
    func timeUntilReset(from now: Date) -> String {
        let calendar = Calendar.current
        let resetDate = calendar.date(byAdding: .day, value: 1, to: usageTracker.lastResetDate) ?? Date()
        let components = calendar.dateComponents([.hour, .minute], from: now, to: resetDate)

        if let hours = components.hour, let minutes = components.minute {
            if hours > 0 {
                return "Resets in \(hours)h \(minutes)m"
            } else {
                return "Resets in \(minutes)m"
            }
        }
        return "Resets soon"
    }
}

