// UpgradeView.swift
import SwiftUI
import RevenueCat
import RevenueCatUI

struct UpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsStore.shared
    @State private var offering: Offering?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let offering {
                    PaywallView(offering: offering)
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading paywall…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 12) {
                        Text("Unable to load paywall")
                            .font(.headline)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        Button("Close") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { loadOffering() }
        .onChange(of: settings.hasUnlimitedSearches) { _, newValue in
            if newValue { dismiss() }
        }
    }

    private func loadOffering() {
        isLoading = true
        Purchases.shared.getOfferings { offerings, error in
            isLoading = false
            if let o = offerings?.current {
                offering = o
            } else {
                errorMessage = error?.localizedDescription ?? "No offerings are available."
            }
        }
    }
}

#Preview {
    UpgradeView()
}