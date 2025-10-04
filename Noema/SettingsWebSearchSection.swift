// SettingsWebSearchSection.swift
import SwiftUI

struct SettingsWebSearchSection: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showInfo = false

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

            if settings.webSearchEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SearXNG web search is enabled for this device.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text("Search requests are proxied through https://search.noemaai.com and are available without quotas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .alert("Web Search button", isPresented: $showInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Allows models to use a privacy-preserving web search API when you tap the globe in chat. Default is ON. In Offline Only mode, the button is disabled.")
        }
    }
}
