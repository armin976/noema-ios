// SettingsStore.swift
import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var webSearchEnabled: Bool { // master toggle (default ON)
        didSet { UserDefaults.standard.set(webSearchEnabled, forKey: "webSearchEnabled") }
    }
    @Published var offlineOnly: Bool { // grays out button and disables tool
        didSet { UserDefaults.standard.set(offlineOnly, forKey: "offlineOnly") }
    }
    @Published var webSearchArmed: Bool { // globe ON/OFF; persists until tapped again
        didSet { UserDefaults.standard.set(webSearchArmed, forKey: "webSearchArmed") }
    }
    @Published var hasUnlimitedSearches: Bool { // whether user has active subscription
        didSet { 
            UserDefaults.standard.set(hasUnlimitedSearches, forKey: "hasUnlimitedSearches")
            
            // If subscription is active, reset any usage limits
            if hasUnlimitedSearches {
                SearchUsageTracker.shared.resetDailyCount()
            }
        }
    }
    
    // Subscription expiration tracking
    @Published var subscriptionExpirationDate: Date? {
        didSet {
            if let date = subscriptionExpirationDate {
                UserDefaults.standard.set(date, forKey: "subscriptionExpirationDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "subscriptionExpirationDate")
            }
        }
    }

    private init() {
        let d = UserDefaults.standard
        self.webSearchEnabled = d.object(forKey: "webSearchEnabled") as? Bool ?? true  // default ON
        self.offlineOnly      = d.object(forKey: "offlineOnly") as? Bool ?? false
        self.webSearchArmed   = d.object(forKey: "webSearchArmed") as? Bool ?? false
        self.hasUnlimitedSearches = d.object(forKey: "hasUnlimitedSearches") as? Bool ?? false
        self.subscriptionExpirationDate = d.object(forKey: "subscriptionExpirationDate") as? Date
        
        // Check subscription status on init
        Task {
            await checkSubscriptionStatus()
        }
    }
    
    // Check if subscription is still valid
    func checkSubscriptionStatus() async {
        // If we have a cached expiration date, check if it's still valid
        if let expirationDate = subscriptionExpirationDate {
            if expirationDate < Date() {
                // Subscription expired
                hasUnlimitedSearches = false
                subscriptionExpirationDate = nil
            }
        }
        
        await RevenueCatManager.shared.refreshEntitlements()
    }
    
    // Helper to check if user can perform web search
    var canPerformWebSearch: Bool {
        return hasUnlimitedSearches || SearchUsageTracker.shared.canSearch()
    }
}


