#if canImport(SwiftUI)
import Combine
import SwiftUI

@MainActor
public final class AutoFlowSettingsStore: ObservableObject {
    @Published public var profile: AutoFlowProfile {
        didSet { persistProfile() }
    }
    @Published public var quickEDAToggle: Bool {
        didSet { persistToggles() }
    }
    @Published public var cleanNullsToggle: Bool {
        didSet { persistToggles() }
    }
    @Published public var plotsToggle: Bool {
        didSet { persistToggles() }
    }
    @Published public var killSwitch: Bool {
        didSet { persistKillSwitch() }
    }

    private let engine: AutoFlowEngine
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, engine: AutoFlowEngine = .shared) {
        self.defaults = defaults
        self.engine = engine
        let storedProfile = defaults.string(forKey: Keys.profile.rawValue)
        self.profile = AutoFlowProfile(rawValue: storedProfile ?? AutoFlowProfile.off.rawValue) ?? .off
        self.quickEDAToggle = defaults.object(forKey: Keys.quickEDAToggle.rawValue) as? Bool ?? true
        self.cleanNullsToggle = defaults.object(forKey: Keys.cleanNullsToggle.rawValue) as? Bool ?? true
        self.plotsToggle = defaults.object(forKey: Keys.plotsToggle.rawValue) as? Bool ?? true
        self.killSwitch = defaults.object(forKey: Keys.killSwitch.rawValue) as? Bool ?? false
        Task { await synchronizeEngine() }
    }

    public func pauseForTenMinutes() {
        Task { await engine.pauseForTenMinutes() }
    }

    public func resume() {
        Task { await engine.resume() }
    }

    private func synchronizeEngine() async {
        await engine.updateProfile(profile)
        await engine.updateToggles(AutoFlowToggles(quickEDAOnMount: quickEDAToggle,
                                                   cleanOnHighNulls: cleanNullsToggle,
                                                   plotsOnMissing: plotsToggle))
        await engine.setKillSwitch(enabled: killSwitch)
    }

    private func persistProfile() {
        defaults.set(profile.rawValue, forKey: Keys.profile.rawValue)
        Task { await engine.updateProfile(profile) }
    }

    private func persistToggles() {
        defaults.set(quickEDAToggle, forKey: Keys.quickEDAToggle.rawValue)
        defaults.set(cleanNullsToggle, forKey: Keys.cleanNullsToggle.rawValue)
        defaults.set(plotsToggle, forKey: Keys.plotsToggle.rawValue)
        Task {
            await engine.updateToggles(
                AutoFlowToggles(quickEDAOnMount: quickEDAToggle,
                                cleanOnHighNulls: cleanNullsToggle,
                                plotsOnMissing: plotsToggle)
            )
        }
    }

    private func persistKillSwitch() {
        defaults.set(killSwitch, forKey: Keys.killSwitch.rawValue)
        Task { await engine.setKillSwitch(enabled: killSwitch) }
    }

    private enum Keys: String {
        case profile = "autoflow.profile"
        case quickEDAToggle = "autoflow.quickEDA"
        case cleanNullsToggle = "autoflow.cleanNulls"
        case plotsToggle = "autoflow.plots"
        case killSwitch = "autoflow.killSwitch"
    }
}

public struct AutoFlowSettingsView: View {
    @StateObject private var store: AutoFlowSettingsStore

    public init(store: AutoFlowSettingsStore = AutoFlowSettingsStore()) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        Section("AutoFlow") {
            Picker("Profile", selection: $store.profile) {
                ForEach(AutoFlowProfile.allCases, id: \.rawValue) { profile in
                    Text(label(for: profile)).tag(profile)
                }
            }
            Toggle("On dataset import run Quick EDA", isOn: $store.quickEDAToggle)
            Toggle("Auto-clean on high nulls", isOn: $store.cleanNullsToggle)
            Toggle("Auto-plots if missing", isOn: $store.plotsToggle)
            Toggle("Kill switch", isOn: $store.killSwitch)
            Button("Pause for 10 minutes") { store.pauseForTenMinutes() }
        }
    }

    private func label(for profile: AutoFlowProfile) -> String {
        switch profile {
        case .off:
            return "Off"
        case .balanced:
            return "Balanced"
        case .aggressive:
            return "Aggressive"
        }
    }
}
#endif
