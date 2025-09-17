// RevenueCatManager.swift
import Foundation
import RevenueCat

@MainActor
final class RevenueCatManager: NSObject, ObservableObject, PurchasesDelegate {
    static let shared = RevenueCatManager()

    // Update to match your RevenueCat dashboard entitlement identifier
    static let entitlementId: String = "Noema Pro"

    private override init() { super.init() }

    static func configure() {
        // Configure RevenueCat with the provided API key
        // If off-grid is enabled, skip configuring networked SDKs
        if UserDefaults.standard.object(forKey: "offGrid") as? Bool == true {
            return
        }
        guard let apiKey = Self.revenueCatAPIKey() else {
            #if DEBUG
            print("RevenueCat API key not configured; skipping Purchases setup.")
            #endif
            return
        }
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = shared
    }

    private static func revenueCatAPIKey() -> String? {
        let envKey = (ProcessInfo.processInfo.environment["REVENUECAT_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !envKey.isEmpty { return envKey }

        let bundleKey = (Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !bundleKey.isEmpty { return bundleKey }

        return nil
    }

    // Delegate: keep SettingsStore in sync when entitlements change
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        // Called from RevenueCat on a background thread — forward to the main actor
        Task { @MainActor [weak self] in
            self?.apply(customerInfo: customerInfo)
        }
    }

    // Refresh entitlements explicitly (e.g., on startup or on demand)
    func refreshEntitlements() async {
        if UserDefaults.standard.object(forKey: "offGrid") as? Bool == true {
            return
        }
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(customerInfo: info)
        } catch {
            // No-op: keep previous state if fetch fails
        }
    }

    private func apply(customerInfo: CustomerInfo) {
        let entitlement = customerInfo.entitlements[Self.entitlementId]
        let isActive = entitlement?.isActive == true
        SettingsStore.shared.hasUnlimitedSearches = isActive

        // Optionally track expiration date if available
        if let exp = entitlement?.expirationDate {
            SettingsStore.shared.subscriptionExpirationDate = exp
        } else {
            SettingsStore.shared.subscriptionExpirationDate = nil
        }
    }
}
