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
    private init() {
        let d = UserDefaults.standard
        self.webSearchEnabled = d.object(forKey: "webSearchEnabled") as? Bool ?? true  // default ON
        self.offlineOnly      = d.object(forKey: "offlineOnly") as? Bool ?? false
        self.webSearchArmed   = d.object(forKey: "webSearchArmed") as? Bool ?? false
    }
}


